//
//  PhysxBindings.m
//  swiftui-test
//
//  Created by utku on 08/12/2022.
//

#import <Foundation/Foundation.h>
#import "shred_ios-Swift.h"

#import "PhysxBindings.h"

#include <iostream>

#ifdef _DEBUG
#undef NDEBUG
#else
#ifndef NDEBUG
#define NDEBUG
#endif
#endif

#include "PxPhysicsAPI.h"
#include <vector>
#include <unordered_map>

using namespace physx;

#pragma mark physx Section

// forward declarations
class ShredPxControllerBehaviorCallback;
void setupFiltering(PxRigidActor* actor, PxU32 filterGroup, PxU32 filterMask);


struct GenericBuffer {
    std::vector<uint8_t> data;
};

class ShredPhysicsErrorCallback : public PxErrorCallback
{
public:
    ShredPhysicsErrorCallback(){};
    ~ShredPhysicsErrorCallback(){};

    virtual void reportError(PxErrorCode::Enum code, const char* message, const char* file, int line){
        printf("%s on file %s at line %d \n", message, file, line);
    }
};

struct PhysxGlobal {
    PxFoundation* gFoundation = nullptr;
    PxPvd* gPvd = nullptr;
    PxPhysics* gPhysics = nullptr;
    PxSceneDesc* gSceneDescriptor = nullptr;
    PxPvdSceneClient* pvdClient = nullptr;
    PxControllerManager* manager = nullptr;
    PxDefaultCpuDispatcher* gDispatcher = nullptr;
    PxScene* gScene = nullptr;
    PxCooking* gChef = nullptr;
    PxDefaultAllocator allocator;
    ShredPhysicsErrorCallback errorCallback;
    
    GenericBuffer cookPhysicsConvexHull(std::vector<float> vertexFloats);
    GenericBuffer cookPhysicsMesh(std::vector<float> vertexFloats);
    
    std::unordered_map<std::string, physx::PxTriangleMesh*> physicsMeshes;
    std::unordered_map<std::string, physx::PxConvexMesh*> physicsConvexHulls;
    
    std::unordered_map<void*, void*> actorMap;
    
    physx::PxTriangleMesh* buildPhysicsMesh(NSData* data, const std::string& meshName);
    physx::PxConvexMesh* buildPhysicsConvexHull(NSData* data, const std::string& meshName);
    
    PxShape* createShapeFromPrototype(EPhysicsComponent* physics, PxMaterial &material);


};
static PhysxGlobal global;


struct ShredPhysicsCallback : public PxSimulationEventCallback {
    // Implements PxSimulationEventCallback
    void onContact(const PxContactPairHeader& pairHeader, const PxContactPair* pairs, PxU32 nbPairs) override {
        static PxContactPairPoint contacts[1];
//        shPhysicsHitResult hitResult;
        pairs->extractContacts(contacts, 1);
//        hitResult.point = bt2glm(contacts[0].position);
//        hitResult.impulse = bt2glm(contacts[0].impulse);
//        hitResult.normal = bt2glm(contacts[0].normal);
        if (pairHeader.actors[0]->getType() == physx::PxActorType::eRIGID_DYNAMIC){
            auto* actor1 = (PxRigidDynamic*)pairHeader.actors[0];
            auto* actor2 = (PxRigidDynamic*)pairHeader.actors[1];
            auto* physics1 = (__bridge EPhysicsComponent*)actor1->userData;
            auto* physics2 = (__bridge EPhysicsComponent*)actor2->userData;
            
            if (physics1 && physics2){
                if (auto callback = [physics1 hitCallback]) {
                    callback(physics2);
                }
                if (auto callback = [physics2 hitCallback]) {
                    callback(physics1);
                }
            }
            
//            hitResult.velocityBeforeImpact = bt2glm(((PxRigidDynamic*)pairHeader.actors[0])->getLinearVelocity());
        }
        //dynamic_cast<PhysicsEvents*>(script->attachedScript)->onHit((uint32_t)otherID, hitResult);
    };

    void onTrigger(PxTriggerPair* pairs, PxU32 count) override {
        int i = 0;
        for (; i < count; i++){
            auto* triggerActor = (PxRigidDynamic*)pairs[i].triggerActor;
            auto* otherActor = (PxRigidDynamic*)pairs[i].otherActor;
            auto* physics1 = (__bridge EPhysicsComponent*)triggerActor->userData;
            auto* physics2 = (__bridge EPhysicsComponent*)otherActor->userData;
            
            if (pairs[i].status == physx::PxPairFlag::eNOTIFY_TOUCH_FOUND){
                if (physics1 && physics2){
                    if (auto callback = [physics1 overlapBeginCallback]) {
                        callback(physics2);
                    }
                    if (auto callback = [physics2 overlapBeginCallback]) {
                        callback(physics1);
                    }
                }
            }else if (pairs[i].status == physx::PxPairFlag::eNOTIFY_TOUCH_LOST){
                if (physics1 && physics2){
                    if (auto callback = [physics1 overlapEndCallback]) {
                        callback(physics2);
                    }
                    if (auto callback = [physics2 overlapEndCallback]) {
                        callback(physics1);
                    }
                }
            }
        }
    };

    void onConstraintBreak(PxConstraintInfo*, PxU32) override {};
    void onWake(PxActor** , PxU32 ) override {};
    void onSleep(PxActor** , PxU32 ) override{
        std::cout << "SLEEP! \n";
    };
    void onAdvance(const PxRigidBody*const*, const PxTransform*, const PxU32) override {};
};

PxFilterFlags SampleSubmarineFilterShader(
        PxFilterObjectAttributes attributes0, PxFilterData filterData0,
        PxFilterObjectAttributes attributes1, PxFilterData filterData1,
        PxPairFlags& pairFlags, const void* constantBlock, PxU32 constantBlockSize)
{
    // let triggers through
    if(PxFilterObjectIsTrigger(attributes0) || PxFilterObjectIsTrigger(attributes1)){
        pairFlags = PxPairFlag::eTRIGGER_DEFAULT;
        return PxFilterFlag::eDEFAULT;
    }
    
    // let non-interacting objects go through each other, but notify as a trigger
    if ((filterData0.word0 & filterData1.word1) == 0 && (filterData0.word1 & filterData1.word0) == 0){
        pairFlags = PxPairFlag::eTRIGGER_DEFAULT;
        return PxFilterFlag::eSUPPRESS;
    }

    // generate contacts for all that were not filtered above
    pairFlags = PxPairFlag::eCONTACT_DEFAULT;
    pairFlags |= PxPairFlag::eNOTIFY_TOUCH_FOUND;

    return PxFilterFlag::eDEFAULT;
}


inline PxVec3 simdToPx(simd_float3 input){
    PxVec3 result;
    result.x = input.x;
    result.y = input.y;
    result.z = input.z;
    return result;
}

inline PxQuat simdToPx(simd_quatf input){
    PxQuat result;
    result.x = input.vector.x;
    result.y = input.vector.y;
    result.z = input.vector.z;
    result.w = input.vector.w;
    return result;
}

simd_float3 pxToSimd(const PxVec3& vec){
    return {vec.x, vec.y, vec.z};
}

simd_quatf pxToSimd(const PxQuat& vec){
    simd_quatf result;
    result.vector.w = vec.w;
    result.vector.x = vec.x;
    result.vector.y = vec.y;
    result.vector.z = vec.z;
    return result;
}



class ShredPxControllerBehaviorCallback
    : public physx::PxControllerBehaviorCallback
{
    physx::PxControllerBehaviorFlags getBehaviorFlags(const physx::PxShape &shape,const physx::PxActor &actor) override{
        if (actor.getType() == physx::PxActorType::eRIGID_DYNAMIC) {
            if (((PxRigidDynamic*)&actor)->getRigidBodyFlags() & PxRigidBodyFlag::eKINEMATIC){
                // we can ride kinematic objects.
                return physx::PxControllerBehaviorFlag::eCCT_CAN_RIDE_ON_OBJECT;
            }
        }
        return physx::PxControllerBehaviorFlag::eCCT_CAN_RIDE_ON_OBJECT;
    }
    
    physx::PxControllerBehaviorFlags getBehaviorFlags(const physx::PxController &controller) override{
        return physx::PxControllerBehaviorFlags(0);
    }
    
    physx::PxControllerBehaviorFlags getBehaviorFlags(const physx::PxObstacle &obstacle) override{
        return physx::PxControllerBehaviorFlag::eCCT_CAN_RIDE_ON_OBJECT;
    }
};

void setupFiltering(PxRigidActor* actor, PxU32 filterGroup, PxU32 filterMask)
{
    PxFilterData filterData;
    filterData.word0 = filterGroup; // word0 = own ID
    filterData.word1 = filterMask;    // word1 = ID mask to filter pairs that trigger a contact callback;
    const PxU32 numShapes = actor->getNbShapes();
    auto** shapes = (PxShape**)malloc(sizeof(void*)*numShapes);
    actor->getShapes(shapes, numShapes);
    for(PxU32 i = 0; i < numShapes; i++){
        PxShape* shape = shapes[i];
        shape->setSimulationFilterData(filterData);
        shape->setQueryFilterData(filterData);
    }
    free(shapes);
}

physx::PxTriangleMesh* PhysxGlobal::buildPhysicsMesh(NSData* data, const std::string& meshName)
{
    if (physicsMeshes.find(meshName) == physicsMeshes.end()) {
        PxU8* dataBytes = (PxU8*)[data bytes];
        PxU32 dataSize = (PxU32)[data length];
        PxDefaultMemoryInputData readBuffer(dataBytes, dataSize);
        auto *mesh = gPhysics->createTriangleMesh(readBuffer);
        if (mesh){
            mesh->acquireReference();
            physicsMeshes[meshName] = mesh;
        }
        return mesh;
    }else{
        return physicsMeshes[meshName];
    }
}

physx::PxConvexMesh* PhysxGlobal::buildPhysicsConvexHull(NSData* data, const std::string& meshName)
{
    if (physicsConvexHulls.find(meshName) == physicsConvexHulls.end()) {
        PxU8* dataBytes = (PxU8*)[data bytes];
        PxU32 dataSize = (PxU32)[data length];
        PxDefaultMemoryInputData readBuffer(dataBytes, dataSize);
        auto* mesh = gPhysics->createConvexMesh(readBuffer);
        physicsConvexHulls[meshName] = mesh;
        return mesh;
    }else{
        return physicsConvexHulls[meshName];
    }
}


GenericBuffer PhysxGlobal::cookPhysicsConvexHull(std::vector<float> vertexFloats)
{

    PxConvexMeshDesc meshDesc;
    std::vector<PxVec3> pxPositions;
    for (uint32_t vi = 0; vi < vertexFloats.size(); vi += 3) {
        pxPositions.emplace_back(
                PxVec3(vertexFloats[vi], vertexFloats[vi + 1], vertexFloats[vi + 2]));
    }
    meshDesc.points.count = (PxU32)pxPositions.size();
    meshDesc.points.stride = sizeof(PxVec3);
    meshDesc.points.data = &pxPositions[0];
    meshDesc.flags = PxConvexFlag::eCOMPUTE_CONVEX;

    PxDefaultMemoryOutputStream writeBuffer;
    PxConvexMeshCookingResult::Enum result;
    GenericBuffer meshBuffer;

    bool status = gChef->cookConvexMesh(meshDesc, writeBuffer, &result);
    if (!status)
        return meshBuffer;
    meshBuffer.data.resize(writeBuffer.getSize());
    memcpy(&meshBuffer.data[0], writeBuffer.getData(), writeBuffer.getSize());
    return meshBuffer;
}

GenericBuffer PhysxGlobal::cookPhysicsMesh(std::vector<float> vertexFloats)
{
    PxTriangleMeshDesc meshDesc;
    std::vector<PxVec3> pxPositions;
    std::vector<PxU32> indices;

    for (uint32_t vi = 0; vi < vertexFloats.size(); vi += 3) {
        pxPositions.emplace_back(
                PxVec3(vertexFloats[vi], vertexFloats[vi + 1], vertexFloats[vi + 2]));
        indices.push_back(vi / 3);
    }
    
    meshDesc.points.count = (PxU32)pxPositions.size();
    meshDesc.points.stride = sizeof(PxVec3);
    meshDesc.points.data = &pxPositions[0];

    meshDesc.triangles.count = (PxU32)(indices.size() / 3);
    meshDesc.triangles.stride = 3 * sizeof(PxU32);
    meshDesc.triangles.data = &indices[0];

    PxDefaultMemoryOutputStream writeBuffer;
    PxTriangleMeshCookingResult::Enum result;
    GenericBuffer meshBuffer;

    bool status = gChef->cookTriangleMesh(meshDesc, writeBuffer, &result);
    if (!status)
        return meshBuffer;

    meshBuffer.data.resize(writeBuffer.getSize());
    memcpy(&meshBuffer.data[0], writeBuffer.getData(), writeBuffer.getSize());
    return meshBuffer;
}

PxShape* PhysxGlobal::createShapeFromPrototype(EPhysicsComponent* physics, PxMaterial &material)
{
    PxShape* p_newCollisionShape = nullptr;

    switch (physics.shape) {
        case PhysicsShapeSPHERE:{
            p_newCollisionShape =
                gPhysics->createShape(PxSphereGeometry(
                                                       physics.scale.x * physics.radius * 0.5f
                                                       ), material, true);
            break;
        }

        case PhysicsShapeBOX:{
            float dimX = physics.box_extents.x * physics.scale.x;
            dimX = (dimX < 0.1f) ? 0.1f : dimX;
            float dimY = physics.box_extents.y * physics.scale.y;
            dimY = (dimY < 0.1f) ? 0.1f : dimY;
            float dimZ = physics.box_extents.z * physics.scale.z;
            dimZ = (dimZ < 0.1f) ? 0.1f : dimZ;
            p_newCollisionShape = gPhysics->createShape(PxBoxGeometry(dimX / 2.0f, dimY / 2.0f, dimZ / 2.0f), material, true);
            break;
        }

        case PhysicsShapeCAPSULE:{
            p_newCollisionShape = gPhysics->createShape(PxCapsuleGeometry(
                                                                          physics.radius * physics.scale.x,
                                                                          physics.height * physics.scale.y
            ), material, true);
            break;
        }

        case PhysicsShapeMESH: {
            std::string physicsMeshName = std::string([physics.physicsMeshName UTF8String]);
            if (!physicsMeshName.empty() && physicsMeshes.find(physicsMeshName) != physicsMeshes.end()){
                auto mesh = physicsMeshes[physicsMeshName];
                PxTriangleMeshGeometry geo(mesh, PxMeshScale(simdToPx(physics.scale)));
                if (!geo.isValid()){
                    std::cout << "Failed to create physics geometry for " << physicsMeshName << "\n";
                    return nullptr;
                }
                p_newCollisionShape = gPhysics->createShape(geo, material, true);
            }
            break;
        }

        case PhysicsShapeCONVEX: {
            std::string physicsMeshName = std::string([physics.physicsMeshName UTF8String]);
            if (!physicsMeshName.empty() && physicsConvexHulls.find(physicsMeshName) != physicsConvexHulls.end()){
                auto mesh = physicsConvexHulls[physicsMeshName];
                PxConvexMeshGeometry geo(mesh, PxMeshScale(simdToPx(physics.scale)));
                p_newCollisionShape = gPhysics->createShape(geo, material, true);
            }
            break;
        }

        case PhysicsShapeCOMPOUND:
        case PhysicsShapeHEIGHTMAP:
        default:
            // unimplemented options
            break;
    }

    return p_newCollisionShape;

}




#define PVD_HOST "10.0.0.15"

#pragma mark ObjC++ Section
@implementation PhysxBindings

+(void)initializePhysicsWorld {
    
    if (global.gFoundation) return;
    
    auto* gCallback = new ShredPhysicsCallback();
    global.gFoundation = PxCreateFoundation(PX_PHYSICS_VERSION, global.allocator, global.errorCallback);
            
    global.gPvd = PxCreatePvd(*global.gFoundation);
    PxPvdTransport* transport = PxDefaultPvdSocketTransportCreate(PVD_HOST, 5425, 1);
    global.gPvd->connect(*transport,PxPvdInstrumentationFlag::eALL);
    
    global.gPhysics = PxCreatePhysics(PX_PHYSICS_VERSION,
                                    *global.gFoundation,
                                    PxTolerancesScale(), false,
                                    global.gPvd);
    PxTolerancesScale scaleTolerances;
    scaleTolerances.length = 1.0f;
    scaleTolerances.speed = 10.0f;
    PxCookingParams chefParams{scaleTolerances};

    global.gChef = PxCreateCooking(PX_PHYSICS_VERSION, *global.gFoundation, chefParams);
    if (!global.gChef)
        std::cout << "PxCreateCooking failed! \n";

    global.gSceneDescriptor = new PxSceneDesc(global.gPhysics->getTolerancesScale());
    global.gSceneDescriptor->gravity = PxVec3(0.0f, -9.81f, 0.0f);
    global.gSceneDescriptor->filterShader    = SampleSubmarineFilterShader;
    global.gSceneDescriptor->simulationEventCallback = gCallback;
    global.gSceneDescriptor->flags |= PxSceneFlag::eENABLE_ACTIVE_ACTORS;

    global.gDispatcher = PxDefaultCpuDispatcherCreate(2);
    global.gSceneDescriptor->cpuDispatcher    = global.gDispatcher;
    global.gScene = global.gPhysics->createScene(*global.gSceneDescriptor);

    global.pvdClient = global.gScene->getScenePvdClient();
    if(global.gPvd->isConnected() && global.pvdClient)
    {
        global.pvdClient->setScenePvdFlag(PxPvdSceneFlag::eTRANSMIT_CONSTRAINTS, true);
        global.pvdClient->setScenePvdFlag(PxPvdSceneFlag::eTRANSMIT_CONTACTS, true);
        global.pvdClient->setScenePvdFlag(PxPvdSceneFlag::eTRANSMIT_SCENEQUERIES, true);
    }

    global.manager = PxCreateControllerManager(*global.gScene);
    
    global.actorMap.clear();

}

+(void)invalidateCaches{
    global.actorMap.clear();
    global.physicsMeshes.clear();
    global.physicsConvexHulls.clear();
}

+(void)addEntityToWorldWithTransform:(ETransformComponent*)transform physics:(EPhysicsComponent*)physics;
{
    PxMaterial* material = global.gPhysics->createMaterial(physics.friction, physics.friction, physics.bounce);
    PxTransform startTransform(simdToPx(transform.global.translation), simdToPx(transform.global.rotation));
    PxShape* shape = global.createShapeFromPrototype(physics, *material);
    
    if (shape) {
        shape->setFlag(PxShapeFlag::eSIMULATION_SHAPE, (physics.is_trigger == 0));
        shape->setFlag(PxShapeFlag::eTRIGGER_SHAPE, (physics.is_trigger != 0));
        
        if (!physics.is_static){
            PxRigidDynamic* newBody = global.gPhysics->createRigidDynamic(startTransform);
            
            newBody->setAngularDamping(physics.angular_damping);
            newBody->setLinearDamping(physics.linear_damping);
            newBody->setRigidDynamicLockFlags((PxRigidDynamicLockFlag::Enum) 0);
            
            newBody->userData = (__bridge void*)physics;
            newBody->setActorFlags(newBody->getActorFlags() | PxActorFlag::eSEND_SLEEP_NOTIFIES);
            newBody->setRigidBodyFlag(PxRigidBodyFlag::eKINEMATIC, physics.is_kinematic == 1);

            PxRigidBodyExt::updateMassAndInertia(*newBody, physics.mass);
            newBody->setMass(physics.mass);
            newBody->setMassSpaceInertiaTensor(PxVec3(1.0f));
            
            newBody->attachShape(*shape);

            global.gScene->addActor(*newBody);
            global.actorMap[(__bridge void*)physics] = newBody;
            
            setupFiltering(newBody, physics.belongs, physics.responds);

            
        }else{
            PxRigidStatic* newBody = global.gPhysics->createRigidStatic(startTransform);
            newBody->attachShape(*shape);
            
            newBody->userData = (__bridge void*)physics;

            global.gScene->addActor(*newBody);
            global.actorMap[(__bridge void*)physics] = newBody;
            setupFiltering(newBody, physics.belongs, physics.responds);
        }
        
        shape->release();
    }
}

+(void)removeEntityWithPhysics:(EPhysicsComponent*)physics
{
    auto indexIterator = global.actorMap.find((__bridge void*)physics);
    if (indexIterator != global.actorMap.end()){
        auto actor = global.actorMap[(__bridge void*)physics];

        if (physics.is_static){
            auto pActor = (PxRigidStatic*)(actor);
            pActor->userData = 0x0;
            global.gScene->removeActor(*pActor);
        }else{
            auto pActor = (PxRigidDynamic*)(actor);
            pActor->userData = 0x0;
            global.gScene->removeActor(*pActor);
        }
        global.actorMap.erase(indexIterator);
        
    } else {
        std::cout << "The requested physics component does not exist in the world! \n";
    }
}

+(void)cookPhysxMesh:(EPhysicsComponent*)physics
{
    if (physics.vertexFloats){
        std::vector<float> meshFloats;
        meshFloats.reserve(physics.vertexFloats.count);
        
        for (id val in physics.vertexFloats){
            float fval = [val floatValue];
            meshFloats.push_back(fval);
        }
        
        auto bufferResult = global.cookPhysicsMesh(meshFloats);
        physics.cookedData = [NSData dataWithBytes:&bufferResult.data[0] length:bufferResult.data.size()];
    }
}

+(void)cookPhysxConvexHull:(EPhysicsComponent*)physics{
    if (physics.vertexFloats){
        std::vector<float> meshFloats;
        meshFloats.reserve(physics.vertexFloats.count);
        
        for (id val in physics.vertexFloats){
            float fval = [val floatValue];
            meshFloats.push_back(fval);
        }
        
        auto bufferResult = global.cookPhysicsConvexHull(meshFloats);
        physics.cookedData = [NSData dataWithBytes:&bufferResult.data[0] length:bufferResult.data.size()];
    }
}

+(void)buildPhysxMesh:(EPhysicsComponent*)physics
{
    global.buildPhysicsMesh(physics.cookedData, std::string([physics.physicsMeshName UTF8String]));
}

+(void)buildPhysxConvexHull:(EPhysicsComponent*)physics
{
    global.buildPhysicsConvexHull(physics.cookedData, std::string([physics.physicsMeshName UTF8String]));
}

+(void)advance:(double)deltaTime{
    @autoreleasepool {
        for (auto& [physics, actor]: global.actorMap){
            auto* phy = (__bridge EPhysicsComponent*)physics;
            if (!phy.is_static && simd_length(phy.impulse) > 0.01f){
                ((PxRigidDynamic*)(actor))->addForce(simdToPx(phy.impulse), PxForceMode::eVELOCITY_CHANGE);
            }
            
            if (phy.is_kinematic) {
                PxVec3 p = simdToPx(phy.physicsTransform.translation);
                PxQuat q = simdToPx(phy.physicsTransform.rotation);
                auto t = PxTransform(p, q);
                ((PxRigidDynamic*)(actor))->setKinematicTarget(t);
            }
            
            phy.impulse = simd_float3(0.0);
        }
        
        // advance the world state
        global.gScene->simulate(deltaTime);
        global.gScene->fetchResults(true);
        
        // retrieve array of actors that moved
        PxU32 nbActiveTransforms;
        PxActor** activeTransforms = global.gScene->getActiveActors(nbActiveTransforms);
        
        for (PxU32 i=0; i < nbActiveTransforms; ++i){
            auto type = activeTransforms[i]->getType();
            
            if (type == physx::PxActorType::eRIGID_DYNAMIC) {
                if (((PxRigidDynamic*)activeTransforms[i])->getRigidBodyFlags() & PxRigidBodyFlag::eKINEMATIC){
                    // skip kinematic objects, we always update their transforms.
                    continue;
                }
                
                PxTransform t = ((PxRigidActor*)activeTransforms[i])->getGlobalPose();
                if (activeTransforms[i]->userData){
                    EPhysicsComponent* phy = (__bridge EPhysicsComponent*)activeTransforms[i]->userData;
                    phy.physicsTransform.translation = pxToSimd(t.p);
                    phy.physicsTransform.rotation = pxToSimd(t.q);
                }
                
            }
            
        }
    }
    
    
}

@end
