//
//  PhysxBindings.h
//  swiftui-test
//
//  Created by utku on 09/12/2022.
//

#ifndef PhysxBindings_h
#define PhysxBindings_h

#import <simd/simd.h>

@class ETransformComponent;
@class EPhysicsComponent;

@interface PhysxBindings : NSObject
+(void)initializePhysicsWorld;
+(void)invalidateCaches;
+(void)cookPhysxMesh:(EPhysicsComponent*)physics;
+(void)advance:(double)deltaTime;
+(void)cookPhysxConvexHull:(EPhysicsComponent*)physics;
+(void)buildPhysxMesh:(EPhysicsComponent*)physics;
+(void)buildPhysxConvexHull:(EPhysicsComponent*)physics;
+(void)addEntityToWorldWithTransform:(ETransformComponent*)transform physics:(EPhysicsComponent*)physics;
+(void)removeEntityWithPhysics:(EPhysicsComponent*)physics;
@end

#endif /* PhysxBindings_h */

