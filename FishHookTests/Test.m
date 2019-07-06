//
//  Test.m
//  FishHookDemo
//
//  Created by roy.cao on 2019/7/5.
//  Copyright © 2019 roy. All rights reserved.
//

#import "Test.h"
#include "dlfcn.h"

@implementation Test

+ (void)printWithStr:(NSString *)str {
    const char *str2 = [str UTF8String];
    printf("%s", str2);
}

@end
