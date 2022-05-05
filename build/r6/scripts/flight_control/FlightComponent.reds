// Hooks

@addField(VehicleObject)
private let m_flightComponent: wref<FlightComponent>;

@wrapMethod(VehicleObject)
protected cb func OnRequestComponents(ri: EntityRequestComponentsInterface) -> Bool {
  EntityRequestComponentsInterface.RequestComponent(ri, n"flightComponent", n"FlightComponent", true);
  wrappedMethod(ri);
}

@wrapMethod(VehicleObject)
protected cb func OnTakeControl(ri: EntityResolveComponentsInterface) -> Bool {
  //FlightLog.Info("[VehicleObject] OnTakeControl: " + this.GetDisplayName());
  this.m_flightComponent = EntityResolveComponentsInterface.GetComponent(ri, n"flightComponent") as FlightComponent;
  // this.m_flightComponent.Toggle(false);
  wrappedMethod(ri);
}

@addMethod(VehicleObject)
public const func GetFlightComponent() -> ref<FlightComponent> {
  return this.m_flightComponent;
}

@addMethod(VehicleObject)
public func ToggleFlightComponent(state: Bool) -> Void {
  this.m_flightComponent.Toggle(state);
}

@addMethod(VehicleObject)
public func GetLocalToWorld() -> Matrix {
  return WorldTransform.ToMatrix(this.GetWorldTransform());
}

@addMethod(VehicleObject)
protected cb func OnPhysicalCollision(evt: ref<PhysicalCollisionEvent>) -> Bool {
  FlightLog.Info("[VehicleObject] OnPhysicalCollision");
  let vehicle = evt.otherEntity as VehicleObject;
  if IsDefined(vehicle) {
    let gameInstance: GameInstance = this.GetGame();
    let player: ref<PlayerPuppet> = GetPlayer(gameInstance);
    let isPlayerMounted = VehicleComponent.IsMountedToProvidedVehicle(gameInstance, player.GetEntityID(), vehicle);
    if isPlayerMounted {
      // FlightController.GetInstance().ProcessImpact(evt.attackData.vehicleImpactForce);
    } else {
      let impulseEvent: ref<PhysicalImpulseEvent> = new PhysicalImpulseEvent();
      impulseEvent.radius = 1.0;
      impulseEvent.worldPosition = Vector4.Vector4To3(evt.worldPosition);
      impulseEvent.worldImpulse = new Vector3(0.0, 0.0, 10000.0);
      vehicle.QueueEvent(impulseEvent);
    }
  }
}

// Custom Classes

public class FlightComponent extends ScriptableDeviceComponent {

  public let m_interaction: ref<InteractionComponent>;
  public let m_healthStatPoolListener: ref<VehicleHealthStatPoolListener>;
  public let m_vehicleBlackboard: wref<IBlackboard>;
  public let m_vehicleTPPCallbackID: ref<CallbackHandle>;

  protected final const func GetVehicle() -> wref<VehicleObject> {
    return this.GetEntity() as VehicleObject;
  }

  private final func OnGameAttach() -> Void {
    //FlightLog.Info("[FlightComponent] OnGameAttach: " + this.GetVehicle().GetDisplayName());
    this.m_interaction = this.FindComponentByName(n"interaction") as InteractionComponent;
    this.m_healthStatPoolListener = new VehicleHealthStatPoolListener();
    this.m_healthStatPoolListener.m_owner = this.GetVehicle();
    GameInstance.GetStatPoolsSystem(this.GetVehicle().GetGame()).RequestRegisteringListener(Cast(this.GetVehicle().GetEntityID()), gamedataStatPoolType.Health, this.m_healthStatPoolListener);
    this.m_vehicleBlackboard = this.GetVehicle().GetBlackboard();
    // QuickhackModule.RequestRefreshQuickhackMenu(this.GetVehicle().GetGame(), this.GetVehicle().GetEntityID());
  }

  private final func OnGameDetach() -> Void {
    //FlightLog.Info("[FlightComponent] OnGameDetach: " + this.GetVehicle().GetDisplayName());
    GameInstance.GetStatPoolsSystem(this.GetVehicle().GetGame()).RequestUnregisteringListener(Cast(this.GetVehicle().GetEntityID()), gamedataStatPoolType.Health, this.m_healthStatPoolListener);
    this.UnregisterVehicleTPPBBListener();
  }
  
  private final func RegisterInputListener() -> Void {
    let playerPuppet: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(this.GetVehicle().GetGame()).GetLocalPlayerMainGameObject() as PlayerPuppet;
    playerPuppet.RegisterInputListener(this, n"VehicleInsideWheel");
    playerPuppet.RegisterInputListener(this, n"VehicleHorn");
  }

  private final func UnregisterInputListener() -> Void {
    let playerPuppet: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(this.GetVehicle().GetGame()).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if IsDefined(playerPuppet) {
      playerPuppet.UnregisterInputListener(this);
    };
  }

  protected final func SetupVehicleTPPBBListener() -> Void {
    let activeVehicleUIBlackboard: wref<IBlackboard>;
    let bbSys: ref<BlackboardSystem>;
    if !IsDefined(this.m_vehicleTPPCallbackID) {
      bbSys = GameInstance.GetBlackboardSystem(this.GetVehicle().GetGame());
      activeVehicleUIBlackboard = bbSys.Get(GetAllBlackboardDefs().UI_ActiveVehicleData);
      this.m_vehicleTPPCallbackID = activeVehicleUIBlackboard.RegisterListenerBool(GetAllBlackboardDefs().UI_ActiveVehicleData.IsTPPCameraOn, this, n"OnVehicleCameraChange");
    };
  }
  
  protected final func UnregisterVehicleTPPBBListener() -> Void {
    let activeVehicleUIBlackboard: wref<IBlackboard>;
    let bbSys: ref<BlackboardSystem>;
    if IsDefined(this.m_vehicleTPPCallbackID) {
      bbSys = GameInstance.GetBlackboardSystem(this.GetVehicle().GetGame());
      activeVehicleUIBlackboard = bbSys.Get(GetAllBlackboardDefs().UI_ActiveVehicleData);
      activeVehicleUIBlackboard.UnregisterListenerBool(GetAllBlackboardDefs().UI_ActiveVehicleData.IsTPPCameraOn, this.m_vehicleTPPCallbackID);
    };
  }

  // callbacks
  
  protected cb func OnMountingEvent(evt: ref<MountingEvent>) -> Bool {
    let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetVehicle().GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
    if mountChild.IsPlayer() {
      this.SetupVehicleTPPBBListener();
      FlightLog.Info("[FlightComponent] OnMountingEvent: " + this.GetVehicle().GetDisplayName());
    }
  }

  protected cb func OnUnmountingEvent(evt: ref<UnmountingEvent>) -> Bool {
    let mountChild: ref<GameObject> = GameInstance.FindEntityByID(this.GetVehicle().GetGame(), evt.request.lowLevelMountingInfo.childId) as GameObject;
    if IsDefined(mountChild) && mountChild.IsPlayer() {
      this.UnregisterVehicleTPPBBListener();
    }
  }

  protected cb func OnDeath(evt: ref<gameDeathEvent>) -> Bool {
    let vehicle: ref<VehicleObject> = this.GetVehicle();
    let gameInstance: GameInstance = vehicle.GetGame();
    let player: ref<PlayerPuppet> = GetPlayer(gameInstance);
    if VehicleComponent.IsMountedToProvidedVehicle(gameInstance, player.GetEntityID(), vehicle) {
      FlightLog.Info("[FlightComponent] OnDeath: " + this.GetVehicle().GetDisplayName());
      FlightController.GetInstance().Disable();
    }
  }

  protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    FlightLog.Info("[FlightComponent] OnAction: " + this.GetVehicle().GetDisplayName());
  }

  protected cb func OnVehicleFlightActivationEvent(evt: ref<VehicleFlightActivationEvent>) -> Bool {
    FlightLog.Info("[FlightComponent] OnVehicleFlightActivationEvent: " + evt.vehicle.GetDisplayName());

  }

  protected cb func OnGridDestruction(evt: ref<VehicleGridDestructionEvent>) -> Bool {
    let vehicle: ref<VehicleObject> = this.GetVehicle();
    let gameInstance: GameInstance = vehicle.GetGame();
    let player: ref<PlayerPuppet> = GetPlayer(gameInstance);
    let isPlayerMounted = VehicleComponent.IsMountedToProvidedVehicle(gameInstance, player.GetEntityID(), vehicle);
    let biggestImpact: Float;
    let desiredChange: Float;
    let gridState: Float;
    let i: Int32 = 0;
    let gridID = 0;
    while i < 16 {
      gridState = evt.state[i];
      desiredChange = evt.desiredChange[i];
      if desiredChange > biggestImpact {
        biggestImpact = desiredChange;
        gridID = i;
      };
      i += 1;
    };
      // FlightLog.Info("[FlightComponent] OnGridDestruction: " + FloatToStringPrec(biggestImpact, 2));
    if isPlayerMounted {
      if biggestImpact > 0.03 {
        FlightController.GetInstance().ProcessImpact(biggestImpact);
      }
    } else {
      this.FireVerticalImpulse(gridID);
      if biggestImpact > 0.30 {
        GameObjectEffectHelper.StartEffectEvent(vehicle, n"explosion");
      }
      // let event = new vehicleDriveToPointEvent();
      // event.targetPos = new Vector3(0.0, 0.0, 0.0);
      // vehicle.QueueEvent(event);
    }
  }

  // protected cb func OnHit(evt: ref<gameHitEvent>) -> Bool {
  //   let vehicle: ref<VehicleObject> = this.GetVehicle();
  //   let gameInstance: GameInstance = vehicle.GetGame();
  //   let player: ref<PlayerPuppet> = GetPlayer(gameInstance);
  //   let isPlayerMounted = VehicleComponent.IsMountedToProvidedVehicle(gameInstance, player.GetEntityID(), vehicle);
  //   FlightLog.Info("[FlightComponent] OnPhysicalCollision: " + FloatToStringPrec(evt.attackData.vehicleImpactForce, 2));
  //   if isPlayerMounted {
  //       FlightController.GetInstance().ProcessImpact(evt.attackData.vehicleImpactForce);
  //   } else {
  //     let impulseEvent: ref<PhysicalImpulseEvent> = new PhysicalImpulseEvent();
  //     impulseEvent.radius = 1.0;
  //     impulseEvent.worldPosition = Vector4.Vector4To3(evt.hitPosition);
  //     impulseEvent.worldImpulse = new Vector3(0.0, 0.0, evt.attackData.vehicleImpactForce);
  //     this.GetVehicle().QueueEvent(impulseEvent);
  //   }
  // }

  
  protected cb func OnInteractionActivated(evt: ref<InteractionActivationEvent>) -> Bool {
    let radialRequest: ref<ResolveQuickHackRadialRequest>;
    if !IsDefined(evt.activator as PlayerPuppet) && !IsDefined(evt.activator as Muppet) {
      return false;
    };
    radialRequest = new ResolveQuickHackRadialRequest();
    this.GetVehicle().GetHudManager().QueueRequest(radialRequest);
  }

  protected cb func OnSetExposeQuickHacks(evt: ref<SetExposeQuickHacks>) -> Bool {
    let request: ref<RefreshActorRequest> = new RefreshActorRequest();
    request.ownerID = this.GetVehicle().GetEntityID();
    this.GetVehicle().GetHudManager().QueueRequest(request);
  }
  
  protected cb func OnActionEngineering(evt: ref<ActionEngineering>) -> Bool {
    // this.FireVerticalImpulse();
  }

  public func OnQuickHackFlightMalfunction(evt: ref<QuickHackFlightMalfunction>) -> EntityNotificationType {
    FlightLog.Info("[FlightComponent] OnQuickHackFlightMalfunction");
    // let type: EntityNotificationType = this.OnQuickHackFlightMalfunction(evt);
    // if Equals(type, EntityNotificationType.DoNotNotifyEntity) {
    //   return type;
    // };
    if evt.IsStarted() {
      // this.ExecutePSAction(this.FireVerticalImpulse());
      // this.FireVerticalImpulse();
    };
    return EntityNotificationType.SendThisEventToEntity;
  }

  // gridID
  // 0 rear left
  // 1 rear right
  // 2 -
  // 3 -
  // 4 door left
  // 5 door right
  // 6 front left
  // 7 front right

  public func FireVerticalImpulse(gridID: Int32, opt impulse: Float) {
    let impulseEvent: ref<PhysicalImpulseEvent> = new PhysicalImpulseEvent();
    impulseEvent.radius = 1.0;
    let offset = new Vector4(0.0, 0.0, 0.0, 0.0);
    if gridID == 0 {
      offset = new Vector4(-0.5, -0.5, 0.0, 0.0);
    }
    if gridID == 1 {
      offset = new Vector4(0.5, -0.5, 0.0, 0.0);
    }
    if gridID == 4 {
      offset = new Vector4(-0.5, 0.0, 0.0, 0.0);
    }
    if gridID == 5 {
      offset = new Vector4(0.5, 0.0, 0.0, 0.0);
    }
    if gridID == 6 {
      offset = new Vector4(-0.5, 0.5, 0.0, 0.0);
    }
    if gridID == 7 {
      offset = new Vector4(0.5, 0.5, 0.0, 0.0);
    }
    if impulse == 0.0 {
      impulse = 1.0;
    }
    // FlightLog.Info("[FlightComponent] FireVerticalImpulse: " + gridID);
    impulseEvent.worldPosition = Vector4.Vector4To3(this.GetVehicle().GetLocalToWorld() * offset);
    impulseEvent.worldImpulse = new Vector3(0.0, 0.0, 10.0 * impulse * this.GetVehicle().GetTotalMass());
    this.GetVehicle().QueueEvent(impulseEvent);
  }

  // protected cb func OnPhysicalCollision(evt: ref<PhysicalCollisionEvent>) -> Bool {
  //   FlightLog.Info("[FlightComponent] OnPhysicalCollision");
  //   let vehicle = this.GetVehicle();
  //   let gameInstance: GameInstance = vehicle.GetGame();
  //   let player: ref<PlayerPuppet> = GetPlayer(gameInstance);
  //   let isPlayerMounted = VehicleComponent.IsMountedToProvidedVehicle(gameInstance, player.GetEntityID(), this);
  //   if isPlayerMounted {
  //     // FlightController.GetInstance().ProcessImpact(evt.attackData.vehicleImpactForce);
  //   } else {
  //     let impulseEvent: ref<PhysicalImpulseEvent> = new PhysicalImpulseEvent();
  //     impulseEvent.radius = 1.0;
  //     impulseEvent.worldPosition = Vector4.Vector4To3(evt.worldPosition);
  //     impulseEvent.worldImpulse = new Vector3(0.0, 0.0, 10000.0);
  //     vehicle.QueueEvent(impulseEvent);
  //   }
  // }

  // protected cb func OnHit(evt: ref<gameHitEvent>) -> Bool {
  //   FlightLog.Info("[FlightComponent] OnHit: " + FloatToStringPrec(evt.attackData.vehicleImpactForce, 2));
  //   let vehicle = this.GetVehicle();
  //   let gameInstance: GameInstance = vehicle.GetGame();
  //   let player: ref<PlayerPuppet> = GetPlayer(gameInstance);
  //   let isPlayerMounted = VehicleComponent.IsMountedToProvidedVehicle(gameInstance, player.GetEntityID(), this);
  //   if isPlayerMounted {
  //     FlightController.GetInstance().ProcessImpact(evt.attackData.vehicleImpactForce);
  //   } else {
  //     let impulseEvent: ref<PhysicalImpulseEvent> = new PhysicalImpulseEvent();
  //     impulseEvent.radius = 1.0;
  //     impulseEvent.worldPosition = Vector4.Vector4To3(evt.hitPosition);
  //     impulseEvent.worldImpulse = new Vector3(0.0, 0.0, evt.attackData.vehicleImpactForce);
  //     vehicle.QueueEvent(impulseEvent);
  //   }
  // }

  // public cb func OnAnyEvent(evt: ref<Event>) {
  //   FlightLog.Info("[FlightComponent] OnAnyEvent: " + ToString(evt.GetClassName()));
  // }

  // hook into sound somehow
  // protected cb func OnVehicleOnPartDetached(evt: ref<VehicleOnPartDetachedEvent>) -> Bool {
  //   let partName: CName = evt.partName;
  //   if Equals(partName, n"Trunk") {
  //     (this.GetPS() as VehicleComponentPS).SetDoorState(EVehicleDoor.trunk, VehicleDoorState.Detached);
  //   } else {
  //     if Equals(partName, n"Hood") {
  //       (this.GetPS() as VehicleComponentPS).SetDoorState(EVehicleDoor.hood, VehicleDoorState.Detached);
  //     } else {
  //       if Equals(partName, n"DoorFrontLeft") || Equals(partName, n"DoorFrontLeft_A") || Equals(partName, n"DoorFrontLeft_B") || Equals(partName, n"DoorFrontLeft_C") {
  //         (this.GetPS() as VehicleComponentPS).SetDoorState(EVehicleDoor.seat_front_left, VehicleDoorState.Detached);
  //       } else {
  //         if Equals(partName, n"DoorFrontRight") || Equals(partName, n"DoorFrontRight_A") || Equals(partName, n"DoorFrontRight_B") || Equals(partName, n"DoorFrontRight_C") {
  //           (this.GetPS() as VehicleComponentPS).SetDoorState(EVehicleDoor.seat_front_right, VehicleDoorState.Detached);
  //         } else {
  //           if Equals(partName, n"DoorBackLeft") {
  //             (this.GetPS() as VehicleComponentPS).SetDoorState(EVehicleDoor.seat_back_left, VehicleDoorState.Detached);
  //           } else {
  //             if Equals(partName, n"DoorBackRight") {
  //               (this.GetPS() as VehicleComponentPS).SetDoorState(EVehicleDoor.seat_back_right, VehicleDoorState.Detached);
  //             };
  //           };
  //         };
  //       };
  //     };
  //   };
  // }
  
  protected final func OnVehicleCameraChange(state: Bool) -> Void {
    FlightController.GetInstance().isTPP = state;
  }


/*  private final func RegisterToHUDManager(shouldRegister: Bool) -> Void {
    let hudManager: ref<HUDManager>;
    let registration: ref<HUDManagerRegistrationRequest>;
    if this.GetVehicle().IsCrowdVehicle() && !this.GetVehicle().ShouldForceRegisterInHUDManager() {
      return;
    };
    hudManager = GameInstance.GetScriptableSystemsContainer(this.GetVehicle().GetGame()).Get(n"HUDManager") as HUDManager;
    if IsDefined(hudManager) {
      registration = new HUDManagerRegistrationRequest();
      registration.SetProperties(this.GetVehicle(), shouldRegister);
      hudManager.QueueRequest(registration);
    };
  }
*/
}

public static func OperatorAdd(a: Vector4, b: Vector3) -> Vector4 {
  return a + Vector4.Vector3To4(b);
}