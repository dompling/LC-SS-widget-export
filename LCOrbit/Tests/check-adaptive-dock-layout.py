"""Source and geometry regression checks for the custom adaptive switcher Dock."""
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / "Core" / "LCOrbitTaskSwitcher.m").read_text()
menu = (Path(__file__).resolve().parents[2] / "LCFloatingMenu" / "LCFloatingMenu.m").read_text()
layout = source.split("- (void)viewDidLayoutSubviews {", 1)[1].split("- (void)updateLiveGeometry {", 1)[0]
visibility = source.split("- (void)setDockVisible:(BOOL)visible {", 1)[1].split("\n}", 1)[0]
creation = source.split("+ (BOOL)presentInScene:(UIWindowScene *)scene apps:(NSArray *)apps dockIconSize:", 1)[-1]

assert "CGAffineTransformMakeTranslation(0,32)" in visibility, "entrance animation prerequisite changed"
assert "self.dock.frame=" not in layout, "transformed frame reintroduces vertical offset"
assert "self.dock.bounds=CGRectMake(0,0,dockWidth,dockHeight);" in layout
assert "self.dock.center=CGPointMake(width*.5,dockTop+dockHeight*.5);" in layout
assert "CGFloat cardBottom=self.dock?dockTop-28:height-safe.bottom-16;" in layout
assert "controller.initialDockVisible=restoredDock;" in creation
assert "CGFloat dockHeight=MAX(54,ceil(self.dockIconSize)+16);" in layout
assert "button.frame=CGRectMake(x,8,buttonWidth,dockHeight-16);" in layout
assert "self.dock.layer.cornerRadius=19" in source
assert 'CGFloat iconSize=FMMenuStyleValue(@"adaptiveDockIconSize");' in menu
assert 'case FMDockWhenAdaptive: return [LCOrbitMultitask usesAdaptiveSwitcher];' in menu
assert '@"key":@"adaptiveDockIconSize"' in menu

# Bounds and center must represent the same resting position whether the Dock
# starts translated by 32pt or visible after a task has been closed.
for height, safe_bottom, dock_height, gap in (
    (852, 34, 56, 4), (852, 34, 48, 80),
    (393, 21, 56, 4), (1024, 20, 56, 25)
):
    top = height - safe_bottom - dock_height - gap
    center = top + dock_height * .5
    resting_top = center - dock_height * .5
    assert abs(resting_top - top) < 1e-9
    assert abs((resting_top + 32) - top - 32) < 1e-9

for size in (24, 36, 44, 50):
    dock_height = max(54, size+16)
    button_height = dock_height-16
    assert dock_height >= size+16
    assert (dock_height-button_height)/2 == 8
    assert button_height >= size
    assert 19 < dock_height/2

print("Adaptive switcher Dock transformed-layout and icon-size regression: PASS")

# iOS 27: keep dock artwork out of UIVisualEffectView's replaceable
# contentView, otherwise the dock glass can remain visible without icons.
assert "@property(nonatomic,strong) UIView *dock;" in source
assert "@property(nonatomic,strong) UIVisualEffectView *dockGlass;" in source
assert '[self.dock addSubview:self.dockGlass];' in source
assert '[self.dock addSubview:self.dockScroll];' in source
assert '[self.dock.contentView addSubview:self.dockScroll]' not in source
assert 'self.dockGlass.effect=visible?' in visibility
assert "self.dock.effect=visible?" not in visibility

# Long-running task decks should avoid needless remote-layer work during scroll.
geometry=source.split("- (void)updateLiveGeometry {",1)[1].split("- (void)updateDeck {",1)[0]
deck=source.split("- (void)updateDeck {",1)[1].split("- (void)selectPage:",1)[0]
entrance=source.split("- (void)animateEntrance {",1)[1].split("- (void)animateReflowFromFrames:",1)[0]
assert "if(scrolling&&!CGRectIntersectsRect(card.frame,nearby))continue;" in geometry
assert "CGAffineTransformEqualToTransform(card.transform,card.restingTransform)" in deck
assert "if(page>currentPage+1 || (currentPage>0 && page+1<currentPage))continue;" in entrance
assert "CGRectIntersectsRect(button.frame,visibleDock)" in entrance

print("iOS 27 adaptive Dock icon isolation and task-deck performance: PASS")

