//
//  RendererCBindings.h
//  nanoshred
//
//  Created by utku on 08/01/2023.
//

#ifndef RendererCBindings_h
#define RendererCBindings_h

@class GenericPrimitive;

@interface RendererCBindings : NSObject
+(void)calculate:(GenericPrimitive*) forPrimitive;
@end

#endif /* RendererCBindings_h */
