#import "LCOrbitSharedTweaksViewController.h"
#import "LCOrbitTweakSync.h"
#import "LCOrbitTweakCenterViews.h"
#import "LCOrbitHost.h"
#import <math.h>

@interface LCOrbitSharedTweaksViewController () <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) UILabel *summaryLabel;
@property(nonatomic,copy) NSArray<NSDictionary *> *inventory;
@property(nonatomic,strong) NSMutableSet<NSString *> *selectedNames;
@property(nonatomic,strong) UIColor *backgroundColor;
@property(nonatomic,strong) UIColor *surfaceColor;
@property(nonatomic,strong) UIColor *textColor;
@property(nonatomic,strong) UIColor *secondaryColor;
@property(nonatomic,strong) UIColor *accentColor;
@property(nonatomic,assign) BOOL busy;
@end

@implementation LCOrbitSharedTweaksViewController
- (instancetype)initWithBackground:(UIColor *)background
                           surface:(UIColor *)surface
                              text:(UIColor *)text
                         secondary:(UIColor *)secondary
                            accent:(UIColor *)accent {
    if((self=[super initWithNibName:nil bundle:nil])) {
        _backgroundColor=background;
        _surfaceColor=surface;
        _textColor=text;
        _secondaryColor=secondary;
        _accentColor=accent;
        _selectedNames=[NSMutableSet set];
        _inventory=@[];
    }
    return self;
}
- (void)updateBackground:(UIColor *)background surface:(UIColor *)surface
                    text:(UIColor *)text secondary:(UIColor *)secondary accent:(UIColor *)accent {
    self.backgroundColor=background;
    self.surfaceColor=surface;
    self.textColor=text;
    self.secondaryColor=secondary;
    self.accentColor=accent;
    if(!self.isViewLoaded) return;
    self.view.backgroundColor=background;
    self.table.backgroundColor=background;
    self.summaryLabel.textColor=secondary;
    self.navigationController.navigationBar.tintColor=accent;
    [self.table reloadData];
    [self updateActions];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"插件管理中心";
    self.view.backgroundColor=self.backgroundColor;
    UITableView *table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    table.translatesAutoresizingMaskIntoConstraints=NO;
    table.backgroundColor=self.backgroundColor;
    table.dataSource=self;
    table.delegate=self;
    table.rowHeight=73;
    table.allowsSelection=YES;
    [self.view addSubview:table];
    [NSLayoutConstraint activateConstraints:@[
        [table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    self.table=table;
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,300,50)];
    UILabel *summary=[UILabel new];
    summary.frame=CGRectMake(22,6,256,38);
    summary.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    summary.numberOfLines=0;
    summary.font=[UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    summary.textColor=self.secondaryColor;
    [header addSubview:summary];
    table.tableHeaderView=header;
    self.summaryLabel=summary;
    if(![LCOrbitHost isHostUI]) {
        summary.text=@"共享插件管理仅在 LiveContainer 主界面开放。";
        return;
    }
    [self reloadInventory];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if([LCOrbitHost isHostUI]) [self reloadInventory];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header=self.table.tableHeaderView;
    if(header && fabs(header.frame.size.width-self.table.bounds.size.width)>1) {
        CGRect frame=header.frame;
        frame.size.width=self.table.bounds.size.width;
        header.frame=frame;
        self.table.tableHeaderView=header;
    }
}
- (BOOL)canSelect:(NSDictionary *)item {
    return [item[@"canShare"] boolValue] || [item[@"canUnshare"] boolValue];
}
- (void)reloadInventory {
    self.inventory=[LCOrbitTweakSync pluginInventory];
    NSMutableSet<NSString *> *available=[NSMutableSet set];
    for(NSDictionary *item in self.inventory)
        if([self canSelect:item]) [available addObject:item[@"name"]];
    [self.selectedNames intersectSet:available];
    [self.table reloadData];
    [self updateActions];
}
- (void)selectAllForShare:(BOOL)share {
    [self.selectedNames removeAllObjects];
    for(NSDictionary *item in self.inventory)
        if([item[share?@"canShare":@"canUnshare"] boolValue])
            [self.selectedNames addObject:item[@"name"]];
    [self.table reloadData];
    [self updateActions];
}
- (void)clearSelection {
    [self.selectedNames removeAllObjects];
    [self.table reloadData];
    [self updateActions];
}
- (NSArray<NSString *> *)selectedForShare:(BOOL)share {
    NSMutableArray<NSString *> *valid=[NSMutableArray array];
    for(NSDictionary *item in self.inventory) {
        if([self.selectedNames containsObject:item[@"name"]] &&
           [item[share?@"canShare":@"canUnshare"] boolValue])
            [valid addObject:item[@"name"]];
    }
    return valid;
}
- (void)updateActions {
    NSUInteger available=0,shared=0;
    for(NSDictionary *item in self.inventory) {
        if([item[@"canShare"] boolValue]) available++;
        if([item[@"shared"] boolValue]) shared++;
    }
    self.summaryLabel.text=[NSString stringWithFormat:
        @"已选 %lu · 可共享 %lu · 已共享 %lu",
        (unsigned long)self.selectedNames.count,(unsigned long)available,(unsigned long)shared];
    __weak typeof(self) weakSelf=self;
    UIAction *share=[UIAction actionWithTitle:
        [NSString stringWithFormat:@"共享选中 (%lu)",(unsigned long)[self selectedForShare:YES].count]
        image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *action) {
            [weakSelf confirmShare:YES];
        }];
    UIAction *revoke=[UIAction actionWithTitle:
        [NSString stringWithFormat:@"取消共享选中 (%lu)",(unsigned long)[self selectedForShare:NO].count]
        image:[UIImage systemImageNamed:@"minus.circle"] identifier:nil handler:^(UIAction *action) {
            [weakSelf confirmShare:NO];
        }];
    if(self.busy || ![self selectedForShare:YES].count)
        share.attributes=UIMenuElementAttributesDisabled;
    if(self.busy || ![self selectedForShare:NO].count)
        revoke.attributes=UIMenuElementAttributesDisabled;
    UIAction *selectAvailable=[UIAction actionWithTitle:@"全选可共享插件"
        image:[UIImage systemImageNamed:@"checkmark.circle"] identifier:nil handler:^(UIAction *action) {
            [weakSelf selectAllForShare:YES];
        }];
    UIAction *selectShared=[UIAction actionWithTitle:@"全选已共享插件"
        image:[UIImage systemImageNamed:@"checkmark.circle.fill"] identifier:nil handler:^(UIAction *action) {
            [weakSelf selectAllForShare:NO];
        }];
    UIAction *clear=[UIAction actionWithTitle:@"清空选择"
        image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil handler:^(UIAction *action) {
            [weakSelf clearSelection];
        }];
    UIAction *refresh=[UIAction actionWithTitle:@"刷新插件列表"
        image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil handler:^(UIAction *action) {
            [weakSelf reloadInventory];
        }];
    if(self.busy) {
        selectAvailable.attributes=UIMenuElementAttributesDisabled;
        selectShared.attributes=UIMenuElementAttributesDisabled;
        clear.attributes=UIMenuElementAttributesDisabled;
        refresh.attributes=UIMenuElementAttributesDisabled;
    }
    UIMenu *menu=[UIMenu menuWithChildren:@[
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline
                    children:@[share,revoke]],
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline
                    children:@[selectAvailable,selectShared,clear,refresh]]
    ]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"操作" menu:menu];
    self.navigationItem.rightBarButtonItem.enabled=!self.busy;
}
- (void)confirmShare:(BOOL)share {
    if(self.busy || ![LCOrbitHost isHostUI]) return;
    NSArray<NSString *> *names=[self selectedForShare:share];
    if(!names.count) return;
    NSString *message=[NSString stringWithFormat:@"共 %lu 个插件 · %@",
        (unsigned long)names.count,share?@"共享选中的本地插件":@"保留私有插件"];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:
        share?@"确认批量共享？":@"确认取消共享？"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:share?@"确认共享":@"取消共享"
        style:share?UIAlertActionStyleDefault:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            LCOrbitSharedTweaksViewController *strongSelf=weakSelf;
            if(!strongSelf || strongSelf.busy) return;
            strongSelf.busy=YES;
            [strongSelf updateActions];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
                NSString *report=[LCOrbitTweakSync applyShare:share names:names];
                dispatch_async(dispatch_get_main_queue(), ^{
                    LCOrbitSharedTweaksViewController *target=weakSelf;
                    if(!target) return;
                    target.busy=NO;
                    [target reloadInventory];
                    if(!target.view.window) return;
                    UIAlertController *done=[UIAlertController alertControllerWithTitle:@"操作结果"
                        message:report preferredStyle:UIAlertControllerStyleAlert];
                    [done addAction:[UIAlertAction actionWithTitle:@"知道了"
                        style:UIAlertActionStyleDefault handler:nil]];
                    [target presentViewController:done animated:YES completion:nil];
                });
            });
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section==0?1:(NSInteger)self.inventory.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section==0?@"App 管理":(self.inventory.count?@"全局插件列表":@"暂无可管理的全局 dylib");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section==0?@"在每个插件的详情中单独设置自动共享。关闭自动共享不会删除已有共享副本。":nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(indexPath.section==0) {
        static NSString *appID=@"LCTweakAppAssignmentCell";
        UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:appID];
        if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:appID];
        cell.textLabel.text=@"按 App 分配插件";
        cell.textLabel.textColor=self.textColor;
        cell.textLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text=@"配置每个 App 的插件";
        cell.detailTextLabel.textColor=self.secondaryColor;
        cell.backgroundColor=self.surfaceColor;
        cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    static NSString *identifier=@"LCSharedTweakCell";
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:identifier];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSDictionary *item=self.inventory[(NSUInteger)indexPath.row];
    NSString *name=item[@"name"];
    BOOL source=[item[@"private"] boolValue],shared=[item[@"shared"] boolValue];
    BOOL loaded=[item[@"loaded"] boolValue],matches=[item[@"matches"] boolValue];
    BOOL blocked=[item[@"blocked"] boolValue];
    BOOL selected=[self.selectedNames containsObject:name];
    cell.textLabel.text=name;
    cell.textLabel.textColor=self.textColor;
    cell.textLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    cell.detailTextLabel.text=[item[@"privateDisabled"] boolValue] && !shared ? @"私有已停用" :
        [item[@"sharedDisabled"] boolValue] && !source ? @"共享已停用" :
        blocked?@"文件异常":
        (shared && !source)?@"仅共享":
        (shared && matches)?@"已共享":
        (shared && source && loaded)?@"版本不同 · 可更新":
        (shared && source)?@"版本不同":
        (source && loaded)?@"可共享":
        @"未加载";
    cell.detailTextLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor=self.secondaryColor;
    cell.backgroundColor=self.surfaceColor;
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    cell.accessoryType=UITableViewCellAccessoryDetailButton;
    cell.imageView.image=[UIImage systemImageNamed:selected?@"checkmark.circle.fill":@"circle"];
    cell.imageView.tintColor=selected?self.accentColor:self.secondaryColor;
    cell.userInteractionEnabled=!self.busy;
    cell.contentView.alpha=[self canSelect:item]?1.0:.56;
    cell.accessibilityLabel=[NSString stringWithFormat:@"%@，%@，%@",
        name,cell.detailTextLabel.text,selected?@"已选择":@"未选择"];
    return cell;
}
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    if(indexPath.section!=1 || self.busy) return;
    NSString *name=self.inventory[(NSUInteger)indexPath.row][@"name"];
    UIViewController *details=[LCOrbitTweakCenterViews
        pluginDetailsForName:name background:self.backgroundColor surface:self.surfaceColor
        text:self.textColor secondary:self.secondaryColor accent:self.accentColor];
    [self.navigationController pushViewController:details animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if(self.busy) return;
    if(indexPath.section==0) {
        UIViewController *apps=[LCOrbitTweakCenterViews
            appAssignmentsWithBackground:self.backgroundColor surface:self.surfaceColor
            text:self.textColor secondary:self.secondaryColor accent:self.accentColor];
        [self.navigationController pushViewController:apps animated:YES];
        return;
    }
    NSDictionary *item=self.inventory[(NSUInteger)indexPath.row];
    if(![self canSelect:item]) return;
    NSString *name=item[@"name"];
    if([self.selectedNames containsObject:name]) [self.selectedNames removeObject:name];
    else [self.selectedNames addObject:name];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateActions];
}
@end
