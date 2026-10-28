#import "LCOrbitLogViewer.h"
#import "LCOrbitTweakAudit.h"
#import "LCOrbitLog.h"

@interface LCOrbitLogViewer ()
@property(nonatomic,assign) BOOL tweakAudit;
@property(nonatomic,strong) UITextView *logText;
@end

@implementation LCOrbitLogViewer
- (instancetype)initWithTweakAudit:(BOOL)tweakAudit {
    if((self=[super initWithNibName:nil bundle:nil])) _tweakAudit=tweakAudit;
    return self;
}
- (NSString *)logKind { return self.tweakAudit?@"tweaks":@"runtime"; }
- (NSString *)logFile { return [LCOrbitLog pathForKind:self.logKind]; }
- (NSData *)allLogData { return [LCOrbitLog dataForKind:self.logKind]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=self.tweakAudit?@"Tweak 加载日志":@"微珠运行日志";
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    UITextView *text=[UITextView new];
    text.editable=NO;
    text.selectable=YES;
    text.alwaysBounceVertical=YES;
    text.translatesAutoresizingMaskIntoConstraints=NO;
    text.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    text.textColor=UIColor.labelColor;
    text.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    text.textContainerInset=UIEdgeInsetsMake(14,12,14,12);
    [self.view addSubview:text];
    [NSLayoutConstraint activateConstraints:@[
        [text.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [text.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [text.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [text.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]
    ]];
    self.logText=text;
    self.navigationItem.rightBarButtonItems=@[
        [[UIBarButtonItem alloc] initWithTitle:@"导出" style:UIBarButtonItemStylePlain target:self action:@selector(exportCurrent)],
        [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(refreshCurrent)]
    ];
    self.navigationItem.leftItemsSupplementBackButton=YES;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
        initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(confirmClear)];
    [self refreshCurrent];
}
- (void)refreshCurrent {
    if(self.tweakAudit) [LCOrbitTweakAudit captureSnapshot];
    NSData *data=[self allLogData];
    NSString *content=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if(!content.length) content=@"暂无日志记录。";
    if(self.tweakAudit) {
        content=[NSString stringWithFormat:
            @"加载状态审计（并非 TweakLoader 原始 NSLog）\n"
             "loaded：路径匹配的已加载镜像\n"
             "not-observed：当前进程未观察到，不代表加载报错\n"
             "basename-match-only：仅名称匹配，来源未确认\n\n%@",content];
    }
    self.logText.text=content;
}
- (void)exportCurrent {
    NSData *data=[self allLogData];
    if(!data.length) { [self showInfo:@"暂无可导出的日志"]; return; }
    NSString *name=self.tweakAudit?@"LCOrbit-Tweaks.json":@"LCOrbit-Runtime.json";
    NSString *destination=[NSTemporaryDirectory() stringByAppendingPathComponent:name];
    if(![data writeToFile:destination atomically:YES]) {
        [self showInfo:@"准备导出文件失败"]; return;
    }
    UIActivityViewController *share=[[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:destination]] applicationActivities:nil];
    UIPopoverPresentationController *popover=share.popoverPresentationController;
    if(popover) {
        popover.sourceView=self.view;
        popover.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),100,1,1);
    }
    [self presentViewController:share animated:YES completion:nil];
}
- (void)confirmClear {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:
        self.tweakAudit?@"清空 Tweak 加载日志？":@"清空微珠运行日志？"
        message:@"只清除此类日志及其旧记录，不会删除插件或设置。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) {
            [LCOrbitLog clearKind:self.logKind];
            // Clearing should not immediately re-create a new audit entry.
            self.logText.text=@"日志已清空。";
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showInfo:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"日志"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
