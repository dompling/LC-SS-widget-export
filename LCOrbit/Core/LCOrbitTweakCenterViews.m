#import "LCOrbitTweakCenterViews.h"
#import "LCOrbitTweakCenter.h"
#import "LCOrbitTweakSync.h"

@interface TCTheme : NSObject
@property(nonatomic,strong) UIColor *background,*surface,*text,*secondary,*accent;
@end
@implementation TCTheme @end
static TCTheme *MakeTheme(UIColor *b,UIColor *s,UIColor *t,UIColor *sub,UIColor *a) {
    TCTheme *theme=[TCTheme new];theme.background=b;theme.surface=s;
    theme.text=t;theme.secondary=sub;theme.accent=a;return theme;
}
static UITableView *MakeTable(UIViewController<UITableViewDelegate,UITableViewDataSource> *owner,TCTheme *theme) {
    UITableView *table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    table.backgroundColor=theme.background;
    table.delegate=owner;table.dataSource=owner;
    table.rowHeight=70;table.translatesAutoresizingMaskIntoConstraints=NO;
    [owner.view addSubview:table];
    [NSLayoutConstraint activateConstraints:@[
        [table.leadingAnchor constraintEqualToAnchor:owner.view.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:owner.view.trailingAnchor],
        [table.topAnchor constraintEqualToAnchor:owner.view.topAnchor],
        [table.bottomAnchor constraintEqualToAnchor:owner.view.bottomAnchor]]];
    return table;
}
static UITableViewCell *Cell(UITableView *table,NSString *identifier,NSString *title,
                             NSString *subtitle,TCTheme *theme) {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:identifier];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.textLabel.text=title;cell.textLabel.textColor=theme.text;
    cell.textLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    cell.detailTextLabel.text=subtitle;cell.detailTextLabel.textColor=theme.secondary;
    cell.detailTextLabel.font=[UIFont systemFontOfSize:12];
    cell.backgroundColor=theme.surface;return cell;
}
static void PresentResult(UIViewController *owner,NSString *title,NSString *message) {
    if(!owner.view.window) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [owner presentViewController:alert animated:YES completion:nil];
}
static NSString *HumanSize(NSNumber *size) {
    return [NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile];
}

@interface TCAppSelectionController : UIViewController <UITableViewDelegate,UITableViewDataSource>
@property(nonatomic,strong) TCTheme *theme;
@property(nonatomic,copy) NSDictionary *guest;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,copy) NSArray<NSDictionary *> *plugins;
@property(nonatomic,strong) NSMutableSet<NSString *> *selected;
@property(nonatomic,assign) BOOL busy;
- (instancetype)initWithGuest:(NSDictionary *)guest theme:(TCTheme *)theme;
@end
@implementation TCAppSelectionController
- (instancetype)initWithGuest:(NSDictionary *)guest theme:(TCTheme *)theme {
    if((self=[super initWithNibName:nil bundle:nil])) {
        _guest=[guest copy];_theme=theme;_selected=[NSMutableSet set];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=self.guest[@"title"];
    self.view.backgroundColor=self.theme.background;
    self.table=MakeTable(self,self.theme);
    if([self.guest[@"conflict"] boolValue]) {
        UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,300,50)];
        UILabel *message=[[UILabel alloc] initWithFrame:CGRectMake(18,4,265,42)];
        message.autoresizingMask=UIViewAutoresizingFlexibleWidth;
        message.numberOfLines=2;message.font=[UIFont systemFontOfSize:12];
        message.textColor=self.theme.secondary;
        message.text=@"请先在 LC 内取消原有的插件文件夹。";
        [header addSubview:message];self.table.tableHeaderView=header;
    }
    [self refresh];
}
- (void)refresh {
    self.plugins=[LCOrbitTweakCenter sourcePluginsForGuest:self.guest];
    [self.selected removeAllObjects];
    for(NSDictionary *item in self.plugins)
        if([item[@"assigned"] boolValue]) [self.selected addObject:item[@"name"]];
    [self.table reloadData];
    __weak typeof(self) weakSelf=self;
    UIAction *all=[UIAction actionWithTitle:@"全选" image:[UIImage systemImageNamed:@"checkmark.circle"]
        identifier:nil handler:^(UIAction *a) {
            for(NSDictionary *item in weakSelf.plugins) [weakSelf.selected addObject:item[@"name"]];
            [weakSelf.table reloadData];
        }];
    UIAction *clear=[UIAction actionWithTitle:@"清空选择" image:[UIImage systemImageNamed:@"xmark.circle"]
        identifier:nil handler:^(UIAction *a) {
            [weakSelf.selected removeAllObjects];[weakSelf.table reloadData];
        }];
    UIBarButtonItem *selection=[[UIBarButtonItem alloc] initWithTitle:@"选择"
        menu:[UIMenu menuWithChildren:@[all,clear]]];
    UIBarButtonItem *save=[[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone
        target:self action:@selector(saveSelection)];
    BOOL conflict=[self.guest[@"conflict"] boolValue];
    selection.enabled=!conflict;save.enabled=!conflict;
    self.navigationItem.rightBarButtonItems=@[save,selection];

}
- (void)saveSelection {
    if(self.busy || [self.guest[@"conflict"] boolValue]) return;
    NSArray *names=[[self.selected allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"保存插件配置？"
        message:[NSString stringWithFormat:@"已选 %lu 个 · 重启 App 生效",
            (unsigned long)names.count] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存配置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        TCAppSelectionController *target=weakSelf;if(!target || target.busy) return;
        target.busy=YES;target.navigationItem.rightBarButtonItems=nil;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            NSString *report=[LCOrbitTweakCenter assignPluginNames:names toGuest:target.guest];
            dispatch_async(dispatch_get_main_queue(),^{
                target.busy=NO;
                for(NSDictionary *app in [LCOrbitTweakCenter guests])
                    if([app[@"folder"] isEqualToString:target.guest[@"folder"]]) {target.guest=app;break;}
                [target refresh];
                PresentResult(target,@"分配结果",report);
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.plugins.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.plugins.count?@"插件列表":@"暂无插件";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *p=self.plugins[(NSUInteger)indexPath.row];
    BOOL selected=[self.selected containsObject:p[@"name"]];
    UITableViewCell *cell=Cell(tableView,@"assigned",p[@"name"],
        [p[@"globalEnabled"] boolValue]?@"全局启用":@"全局停用",self.theme);
    cell.imageView.image=[UIImage systemImageNamed:selected?@"checkmark.circle.fill":@"circle"];
    cell.imageView.tintColor=selected?self.theme.accent:self.theme.secondary;
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    cell.contentView.alpha=[self.guest[@"conflict"] boolValue]?.55:1.0;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if(self.busy || [self.guest[@"conflict"] boolValue]) return;
    NSString *name=self.plugins[(NSUInteger)indexPath.row][@"name"];
    if([self.selected containsObject:name]) [self.selected removeObject:name];
    else [self.selected addObject:name];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}
@end

@interface TCAppListController : UIViewController <UITableViewDelegate,UITableViewDataSource>
@property(nonatomic,strong) TCTheme *theme;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,copy) NSArray<NSDictionary *> *guests;
- (instancetype)initWithTheme:(TCTheme *)theme;
@end
@implementation TCAppListController
- (instancetype)initWithTheme:(TCTheme *)theme {
    if((self=[super initWithNibName:nil bundle:nil])) _theme=theme;
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"按 App 分配插件";
    self.view.backgroundColor=self.theme.background;self.table=MakeTable(self,self.theme);
    self.table.rowHeight=75;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.guests=[LCOrbitTweakCenter guests];[self.table reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.guests.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.guests.count?@"应用列表":@"暂无应用";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *app=self.guests[(NSUInteger)indexPath.row];
    NSString *subtitle=[app[@"conflict"] boolValue]?
        @"使用中：LC 原有插件文件夹":
        [NSString stringWithFormat:@"%@ · 已分配 %@ 个",
            [app[@"shared"] boolValue]?@"共享 Guest":@"私有 Guest",app[@"assigned"]];
    UITableViewCell *cell=Cell(tableView,@"guest",app[@"title"],subtitle,self.theme);
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.navigationController pushViewController:
        [[TCAppSelectionController alloc] initWithGuest:self.guests[(NSUInteger)indexPath.row] theme:self.theme]
        animated:YES];
}
@end

@interface TCPluginDetailController : UIViewController <UITableViewDelegate,UITableViewDataSource>
@property(nonatomic,strong) TCTheme *theme;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,copy) NSArray<NSDictionary *> *backups;
- (instancetype)initWithName:(NSString *)name theme:(TCTheme *)theme;
@end
@implementation TCPluginDetailController
- (instancetype)initWithName:(NSString *)name theme:(TCTheme *)theme {
    if((self=[super initWithNibName:nil bundle:nil])) {_name=[name copy];_theme=theme;}
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"插件详情";
    self.view.backgroundColor=self.theme.background;self.table=MakeTable(self,self.theme);
    self.table.rowHeight=64;[self refresh];
}
- (void)refresh {
    self.backups=[LCOrbitTweakCenter backupsForPlugin:self.name];
    [self.table reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section==0?3:section==1?4:(NSInteger)self.backups.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"插件信息",@"操作",@"历史备份"][section];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger section=indexPath.section,row=indexPath.row;
    if(section==0) {
        if(row==0) {
            UITableViewCell *c=Cell(tableView,@"name",self.name,nil,self.theme);
            c.selectionStyle=UITableViewCellSelectionStyleNone;return c;
        }
        BOOL shared=row==2;
        NSDictionary *info=[LCOrbitTweakCenter pluginInfo:self.name shared:shared];
        NSString *status=[info[@"exists"] boolValue]?
            [NSString stringWithFormat:@"%@ · %@",
                [info[@"enabled"] boolValue]?@"已启用":@"已停用",HumanSize(info[@"size"])]:
            @"无副本";
        UITableViewCell *c=Cell(tableView,@"fileInfo",shared?@"共享全局版本":@"私有全局版本",status,self.theme);
        c.accessoryType=[info[@"exists"] boolValue]?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
        return c;
    }
    if(section==1) {
        NSArray *labels=@[@"私有插件 · 启用/停用",@"共享插件 · 启用/停用",@"备份私有版本",@"备份共享版本"];
        UITableViewCell *c=Cell(tableView,@"action",labels[(NSUInteger)row],
            nil,self.theme);
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;
    }
    NSDictionary *b=self.backups[(NSUInteger)row];
    NSDateFormatter *format=[NSDateFormatter new];format.dateStyle=NSDateFormatterShortStyle;
    format.timeStyle=NSDateFormatterShortStyle;
    NSString *subtitle=[NSString stringWithFormat:@"%@ · %@ · %@",
        [b[@"shared"] boolValue]?@"共享":@"私有",
        HumanSize(b[@"size"]),[format stringFromDate:b[@"date"]]];
    UITableViewCell *c=Cell(tableView,@"backup",b[@"file"],subtitle,self.theme);
    c.textLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;
    c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;
}
- (void)confirmTitle:(NSString *)title message:(NSString *)message destructive:(BOOL)destructive
              action:(NSString *(^)(void))work {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确认" style:destructive?UIAlertActionStyleDestructive:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            NSString *result=work();[weakSelf refresh];PresentResult(weakSelf,@"操作结果",result);
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.section==0) {
        if(indexPath.row==0) return;
        BOOL shared=indexPath.row==2;
        NSDictionary *info=[LCOrbitTweakCenter pluginInfo:self.name shared:shared];
        if(![info[@"exists"] boolValue]) return;
        NSDateFormatter *format=[NSDateFormatter new];format.dateStyle=NSDateFormatterMediumStyle;format.timeStyle=NSDateFormatterMediumStyle;
        PresentResult(self,shared?@"共享插件文件":@"私有插件文件",
            [NSString stringWithFormat:@"状态：%@\n大小：%@\n修改时间：%@\n路径：%@",
                [info[@"enabled"] boolValue]?@"启用":@"停用",HumanSize(info[@"size"]),
                [format stringFromDate:info[@"date"]],info[@"path"]]);
        return;
    }
    if(indexPath.section==1) {
        NSInteger row=indexPath.row;
        BOOL shared=row==1 || row==3;
        if(row>=2) {
            [self confirmTitle:@"备份插件" message:nil
                destructive:NO action:^NSString *{return [LCOrbitTweakCenter backupPlugin:self.name shared:shared];}];
        } else {
            UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"插件状态"
                message:nil
                preferredStyle:UIAlertControllerStyleActionSheet];
            __weak typeof(self) weakSelf=self;
            for(NSNumber *enabled in @[@YES,@NO]) {
                BOOL on=enabled.boolValue;
                [sheet addAction:[UIAlertAction actionWithTitle:on?@"启用":@"停用"
                    style:on?UIAlertActionStyleDefault:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
                    [weakSelf confirmTitle:on?@"启用插件":@"停用插件"
                        message:@"重启 App 后生效。"
                        destructive:!on action:^NSString *{
                            return [LCOrbitTweakCenter setPlugin:weakSelf.name enabled:on shared:shared];
                        }];
                }]];
            }
            [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            if(sheet.popoverPresentationController) {
                sheet.popoverPresentationController.sourceView=tableView;
                sheet.popoverPresentationController.sourceRect=[tableView rectForRowAtIndexPath:indexPath];
            }
            [self presentViewController:sheet animated:YES completion:nil];
        }
    } else {
        NSDictionary *b=self.backups[(NSUInteger)indexPath.row];
        NSString *filename=b[@"file"];
        BOOL shared=[b[@"shared"] boolValue];
        [self confirmTitle:@"恢复插件备份"
            message:[NSString stringWithFormat:@"恢复 %@ 的%@备份？",
                self.name,shared?@"共享":@"私有"]
            destructive:YES action:^NSString *{
                return [LCOrbitTweakCenter restorePlugin:self.name backup:filename shared:shared];
            }];
    }
}
@end
@implementation LCOrbitTweakCenterViews
+ (UIViewController *)appAssignmentsWithBackground:(UIColor *)background surface:(UIColor *)surface
    text:(UIColor *)text secondary:(UIColor *)secondary accent:(UIColor *)accent {
    return [[TCAppListController alloc] initWithTheme:MakeTheme(background,surface,text,secondary,accent)];
}
+ (UIViewController *)pluginDetailsForName:(NSString *)name background:(UIColor *)background
    surface:(UIColor *)surface text:(UIColor *)text secondary:(UIColor *)secondary accent:(UIColor *)accent {
    return [[TCPluginDetailController alloc] initWithName:name theme:MakeTheme(background,surface,text,secondary,accent)];
}
@end
