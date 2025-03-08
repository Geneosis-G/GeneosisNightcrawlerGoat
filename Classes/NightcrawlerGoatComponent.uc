class NightcrawlerGoatComponent extends GGMutatorComponent;

var GGGoat gMe;
var GGMutator myMut;
var bool willTeleport;
var bool isTeleporting;
var bool wasRagdoll;
var vector lastVelocity;
var SoundCue tpSound;
var ParticleSystem tpEffect;
var TeleportSphere tpSphere;
var float tpRange, tpTime, radius, height;

var Material mAngelMaterial;
var MaterialInstanceConstant mMaterialInstanceConstant;

var Material stealthMaterial;
var bool stealthActive;
var SoundCue stealthOff;
var SoundCue stealthOn;

var array<MaterialMeshPair> mMaterialAndMeshes;

/**
 * See super.
 */
function AttachToPlayer( GGGoat goat, optional GGMutator owningMutator )
{
	super.AttachToPlayer(goat, owningMutator);

	if(mGoat != none)
	{
		gMe=goat;
		myMut=owningMutator;

		gMe.mMinWallRunZ=0;
		gMe.mWallRunZ=600;
		gMe.mWallRunBoostZ=400;
		gMe.mWallJumpZ=1200;
		gMe.mWallRunSpeed=900;
		gMe.mTransparentMaterial=stealthMaterial;

		MakeSkinBlue();
	}
}

function MakeSkinBlue()
{
	local color darkBlue;
	local LinearColor newColor;

	gMe.mesh.SetMaterial(0, mAngelMaterial);
	mMaterialInstanceConstant = gMe.mesh.CreateAndSetMaterialInstanceConstant(0);
	darkBlue = MakeColor(3, 32, 53, 255);
	newColor = ColorToLinearColor(darkBlue);
	mMaterialInstanceConstant.SetVectorParameterValue('color', newColor);
}

function KeyState( name newKey, EKeyState keyState, PlayerController PCOwner )
{
	local GGPlayerInputGame localInput;

	if(PCOwner != gMe.Controller)
		return;

	localInput = GGPlayerInputGame( PCOwner.PlayerInput );

	if( keyState == KS_Down )
	{
		if( localInput.IsKeyIsPressed( "GBA_Sprint", string( newKey ) ) || newKey == 'XboxTypeS_RightThumbStick')
		{
			PrepareTeleport(true);
		}

		if( localInput.IsKeyIsPressed( "GBA_ToggleRagdoll", string( newKey ) ) )
		{
			gMe.SetTimer(1.f, false, NameOf( ToggleStealth ), self);
		}
	}
	else if( keyState == KS_Up )
	{
		if( localInput.IsKeyIsPressed( "GBA_Sprint", string( newKey ) ) || newKey == 'XboxTypeS_RightThumbStick')
		{
			PrepareTeleport(false);
		}

		if( localInput.IsKeyIsPressed( "GBA_ToggleRagdoll", string( newKey ) ) )
		{
			if(gMe.IsTimerActive(NameOf( ToggleStealth ), self))
			{
				gMe.ClearTimer(NameOf( ToggleStealth ), self);
			}
		}
	}
}

function ToggleStealth()
{
	mGoat.PlaySound( stealthActive ? stealthOff : stealthOn );

	stealthActive = !stealthActive;
	gMe.SwitchMaterial( stealthActive );
	//ensure camera doesn't override our stuff
	gMe.mLockMaterial = stealthActive;
}

event TickMutatorComponent( float deltaTime )
{
	super.TickMutatorComponent(deltaTime);

	gMe.GetBoundingCylinder( radius, height );

	if(tpSphere == none)
	{
		tpSphere=gMe.Spawn(class'TeleportSphere');
		tpSphere.SetHidden(!willTeleport);
	}

	CalcSphereLocation();
}

/**
 * See super.
 */
function OnChangeState( Actor actorInState, name newStateName )
{
	super.OnChangeState( actorInState, newStateName );

	if(willTeleport && actorInState == gMe)
	{
		if(newStateName == 'AbilityHorn')
		{
			StartTeleport();
		}
	}
}

function CalcSphereLocation()
{
	local vector dest;
	local vector offset, camLocation;
	local rotator camRotation;
	local vector traceStart, traceEnd, hitLocation, hitNormal;
	local Actor hitActor;

	if(gMe.Controller != none)
	{
		GGPlayerControllerGame( gMe.Controller ).PlayerCamera.GetCameraViewPoint( camLocation, camRotation );
	}
	else
	{
		camLocation=gMe.Location;
		camRotation=gMe.Rotation;
	}
	traceStart = camLocation;
	traceEnd = traceStart;
	traceEnd += (vect(1, 0, 0)*tpRange) >> (camRotation + (rot(1, 0, 0)*10*DegToUnrRot));

	foreach gMe.TraceActors( class'Actor', hitActor, hitLocation, hitNormal, traceEnd, traceStart )
	{
		if(hitActor == tpSphere || hitActor == gMe || hitActor.Base == gMe)
		{
			continue;
		}

		break;
	}

	if(hitActor == none)
	{
		hitLocation=traceEnd;
	}

	offset=hitNormal;
	offset.Z=0;
	dest = hitLocation + Normal(offset)*radius;

	tpSphere.SetLocation(dest);
}

function PrepareTeleport(bool active)
{
	if(active == willTeleport)
	{
		return;
	}

	willTeleport=active;
	tpSphere.SetHidden(!willTeleport);
}

//Pre-teleport animation
function StartTeleport()
{
	if(!willTeleport || isTeleporting)
	{
		return;
	}

	isTeleporting=true;
	gMe.SetHidden(true);

	lastVelocity=gMe.Velocity;
	wasRagdoll=gMe.mIsRagdoll;
	if(wasRagdoll)
	{
		gMe.mesh.PhysicsWeight = 0;
		gMe.mTerminatingRagdoll = false;
		gMe.CollisionComponent = gMe.Mesh;
		gMe.SetPhysics( PHYS_Falling );
		gMe.SetRagdoll( false );
	}
	gMe.mIsRagdollAllowed=false;
	gMe.SetPhysics(PHYS_None);
	gMe.Velocity=vect(0, 0, 0);

	gMe.PlaySound( tpSound );
	gMe.WorldInfo.MyEmitterPool.SpawnEmitter( tpEffect, gMe.Location );
	gMe.SetTimer(tpTime, false, NameOf( Teleport ), self);
}

function Teleport()
{
	local vector dest, destUp, destAway, oldLoc;
	local float i, j;

	dest=tpSphere.Location;
	dest.Z+=height;
	destAway=dest;
	destUp=dest;

	oldLoc=gMe.Location;
	SetPosition(dest);

	if(gMe.Location != dest)
	{
		for(i=0 ; i<=10 ; i+=1)
		{
			//myMut.WorldInfo.Game.Broadcast(myMut, "try away");
			if(i>0)
			{
				destAway=oldLoc-dest;
				//destAway.Z=0.f;
				destAway=Normal(destAway)*(i*radius/10.f);
				SetPosition(destAway);
				if(gMe.Location == destAway)
				{
					break;
				}
			}

			for(j=0 ; j<=10 ; j+=1)
			{
				if(i != j && i != 0 && j != 0)
				{
					continue;
				}
				//myMut.WorldInfo.Game.Broadcast(myMut, "try up");
				destUp=destAway;
				destUp.Z+=j*height/10.f;
				SetPosition(destUp);
				if(gMe.Location == destUp)
				{
					break;
				}
			}

			if(gMe.Location == destUp)
			{
				break;
			}
		}
	}

	if(IsTooFarFromDest(gMe.Location, dest))
	{
		SetPosition(oldLoc);
	}

	//myMut.WorldInfo.Game.Broadcast(myMut, "tmp=" $ tmp);
	//myMut.WorldInfo.Game.Broadcast(myMut, "dest=" $ dest);
	//myMut.WorldInfo.Game.Broadcast(myMut, "Location=" $ gMe.Location);

	//Post-teleport animation
	EndTeleport();
}

function EndTeleport()
{
	gMe.WorldInfo.MyEmitterPool.SpawnEmitter( tpEffect, gMe.Location );

	gMe.SetPhysics(PHYS_Falling);
	gMe.Velocity=lastVelocity;
	gMe.mIsRagdollAllowed=true;
	/*if(wasRagdoll)
	{
		gMe.SetRagdoll( true );
	}*/
	gMe.SetHidden(false);
	isTeleporting = false;
}

function SetPosition(vector newLoc)
{
	gMe.SetLocation(newLoc);
	gMe.Mesh.SetRBPosition(newLoc);
}

function bool IsTooFarFromDest(vector pos, vector dest)
{
	local float dist;

	dist=VSize(pos-dest);

	return (dist*dist > radius*radius + height*height + 1.f);
}

defaultproperties
{
	tpRange=2000.f
	tpTime=0.4f
	tpSound=SoundCue'Goat_Sounds.Cue.Fan_Jump_Cue'
	tpEffect=ParticleSystem'MMO_Effects.Effects.Effects_RowSplash_01'
	mAngelMaterial=Material'goat.Materials.Goat_Mat_03'

	stealthMaterial=Material'NightcrawlerGoat.Materials.Stealth_Mat';
	stealthOn=SoundCue'MMO_SFX_SOUND.Cue.SFX_Rogue_Stealth_On_Cue'
	stealthOff=SoundCue'MMO_SFX_SOUND.Cue.SFX_Rogue_Stealth_Off_Cue'
}