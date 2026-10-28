#import <Foundation/Foundation.h>
#include "host-settings-policy.inc"
static int Count,Failures;
static void Check(BOOL ok,const char *message) { Count++;if(!ok){Failures++;fprintf(stderr,"FAIL: %s\n",message);} }
int main(void) { @autoreleasepool {
    Check(IsDataManagementTitle(@"数据管理"),"zh-CN data management recognized");
    Check(IsDataManagementTitle(@"Data Management"),"English recognized");
    Check(IsDataManagementTitle(@"資料管理"),"traditional Chinese recognized");
    Check(IsDataManagementTitle(@" 数据管理 "),"localized row trimming");
    Check(!IsDataManagementTitle(@"存储管理"),"storage row must not open settings");
    Check(!IsDataManagementTitle(@"Settings"),"settings tab must not open recovery");
    Check(!IsDataManagementTitle(nil),"nil label excluded");
    Check(HostGestureAllowed(YES,YES,NO),"foreground LC host enabled");
    Check(!HostGestureAllowed(NO,YES,NO),"guest excluded");
    Check(!HostGestureAllowed(YES,NO,NO),"background excluded");
    Check(!HostGestureAllowed(YES,YES,YES),"active LiveProcess window excluded");
    printf("LC host recovery gesture policy: %d assertions, %d failures\n",Count,Failures);
    return Failures?1:0;
}}
