#import "MGSettingsViewController.h"
#import "LauncherPreferences.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import <objc/runtime.h>

@interface MGSettingsViewController () <UIPickerViewDataSource, UIPickerViewDelegate>

@property(nonatomic) NSArray *sectionItems;
@property(nonatomic) UIPickerView *pickerView;
@property(nonatomic) UITextField *activeField;

@end

static NSString *mgKey(NSString *key) {
    return [NSString stringWithFormat:@"mg.%@", key];
}

static NSInteger mgInt(NSString *key, NSInteger def) {
    id val = getPrefObject(mgKey(key));
    return val ? [val integerValue] : def;
}

static BOOL mgBool(NSString *key, BOOL def) {
    id val = getPrefObject(mgKey(key));
    return val ? [val boolValue] : def;
}

static void setMG(NSString *key, id value) {
    setPrefObject(mgKey(key), value);
}

typedef NS_ENUM(NSInteger, MGCellType) {
    MGCellSwitch,
    MGCellPicker,
    MGCellTextField
};

@implementation MGSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileGlues";

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;

    self.sectionItems = @[
        // Section 0: Basic
        @[
            @{@"key": @"maxGlslCacheSize", @"label": @"Max GLSL Cache Size", @"desc": @"Enter -1 to disable. Unit: Megabytes (MB)",
              @"type": @(MGCellTextField), @"def": @2, @"placeholder": @"-1 or MB"},
        ],
        // Section 1: ANGLE
        @[
            @{@"key": @"enableAngle", @"label": @"Use ANGLE as OpenGL ES driver",
              @"type": @(MGCellPicker),
              @"options": @[@"Prefer Disabled", @"Prefer Enabled", @"Disabled", @"Enabled"],
              @"values": @[@0, @1, @2, @3], @"def": @0},
        ],
        // Section 2: Error
        @[
            @{@"key": @"ignoreError", @"label": @"OpenGL Error Setting",
              @"type": @(MGCellPicker),
              @"options": @[@"Auto", @"Do not ignore", @"Ignore shader/program error", @"Ignore all errors"],
              @"values": @[@0, @1, @2, @3], @"def": @0},
        ],
        // Section 3: MultiDraw
        @[
            @{@"key": @"multidrawMode", @"label": @"MultiDraw Emulation",
              @"type": @(MGCellPicker),
              @"options": @[@"Auto", @"Prefer Indirect", @"Prefer BaseVertex", @"Prefer MultiDraw Indirect", @"Force DrawElements", @"Prefer Compute"],
              @"values": @[@0, @1, @2, @3, @4, @5], @"def": @0},
        ],
        // Section 4: OpenGL Version
        @[
            @{@"key": @"customGLVersion", @"label": @"Custom target OpenGL Version",
              @"type": @(MGCellPicker),
              @"options": @[@"Disable", @"OpenGL 4.6", @"OpenGL 4.5", @"OpenGL 4.4", @"OpenGL 4.3", @"OpenGL 4.2", @"OpenGL 4.1", @"OpenGL 3.3", @"OpenGL 3.2"],
              @"values": @[@0, @46, @45, @44, @43, @42, @41, @33, @32], @"def": @0},
        ],
        // Section 5: ANGLE Depth Clear
        @[
            @{@"key": @"angleDepthClearFix", @"label": @"ANGLE Depth Clear Workaround",
              @"type": @(MGCellPicker),
              @"options": @[@"Disable", @"Enable workaround #1"],
              @"values": @[@0, @1], @"def": @0},
        ],
        // Section 6: Extensions
        @[
            @{@"key": @"extComputeShader", @"label": @"Enable Incomplete 'ARB_compute_shader' Extension",
              @"type": @(MGCellSwitch), @"def": @NO},
            @{@"key": @"extTimerQuery", @"label": @"Disable Recommended 'timer_query' Extension",
              @"desc": @"When enabled, timer_query is disabled",
              @"type": @(MGCellSwitch), @"def": @NO, @"inverted": @YES},
            @{@"key": @"extDirectStateAccess", @"label": @"Enable Advanced 'direct_state_access' Extension",
              @"type": @(MGCellSwitch), @"def": @YES},
            @{@"key": @"fsr1Setting", @"label": @"(Experimental) Enable built-in FSR1",
              @"type": @(MGCellSwitch), @"def": @NO},
        ],
    ];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"Done", nil)
        style:UIBarButtonItemStyleDone target:self action:@selector(dismissView)];
}

- (void)dismissView {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sectionItems.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Cache";
        case 1: return @"ANGLE";
        case 2: return @"Error";
        case 3: return @"MultiDraw";
        case 4: return @"OpenGL Version";
        case 5: return @"Depth Clear";
        case 6: return @"Extensions";
        default: return @"";
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.sectionItems[section] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.sectionItems[indexPath.section][indexPath.row];
    NSString *key = item[@"key"];
    MGCellType type = [item[@"type"] integerValue];

    NSString *cellId = [NSString stringWithFormat:@"c%ld-%ld", (long)indexPath.section, (long)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }

    cell.textLabel.text = item[@"label"];
    cell.detailTextLabel.text = item[@"desc"];
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    switch (type) {
        case MGCellSwitch: {
            UISwitch *sw = [[UISwitch alloc] init];
            BOOL inverted = [item[@"inverted"] boolValue];
            BOOL val = mgBool(key, [item[@"def"] boolValue]);
            sw.on = inverted ? !val : val;
            sw.tag = inverted ? 1 : 0;
            [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
            objc_setAssociatedObject(sw, @"key", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case MGCellPicker: {
            NSInteger val = mgInt(key, [item[@"def"] integerValue]);
            NSArray *values = item[@"values"];
            NSArray *options = item[@"options"];
            NSInteger idx = [values indexOfObject:@(val)];
            if (idx == NSNotFound) idx = 0;
            cell.detailTextLabel.text = item[@"desc"];

            UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 140, 30)];
            vl.text = options[idx];
            vl.textAlignment = NSTextAlignmentRight;
            vl.textColor = self.view.tintColor;
            vl.font = [UIFont systemFontOfSize:14];
            vl.adjustsFontSizeToFitWidth = YES;
            vl.minimumScaleFactor = 0.7;
            cell.accessoryView = vl;
            break;
        }
        case MGCellTextField: {
            NSInteger val = mgInt(key, [item[@"def"] integerValue]);
            UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 80, 30)];
            tf.text = [NSString stringWithFormat:@"%ld", (long)val];
            tf.textAlignment = NSTextAlignmentRight;
            tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            tf.borderStyle = UITextBorderStyleRoundedRect;
            tf.delegate = self;
            objc_setAssociatedObject(tf, @"key", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(tf, @"def", item[@"def"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [tf addTarget:self action:@selector(onTextEdit:) forControlEvents:UIControlEventEditingDidEnd];
            cell.accessoryView = tf;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *item = self.sectionItems[indexPath.section][indexPath.row];
    MGCellType type = [item[@"type"] integerValue];
    if (type != MGCellPicker) return;

    NSString *key = item[@"key"];
    UIView *cell = [tableView cellForRowAtIndexPath:indexPath];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item[@"label"]
        message:item[@"desc"] preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *options = item[@"options"];
    NSArray *values = item[@"values"];
    NSInteger cur = mgInt(key, [item[@"def"] integerValue]);

    for (NSInteger i = 0; i < options.count; i++) {
        NSInteger val = [values[i] integerValue];
        NSString *title = (val == cur) ? [@"✓ " stringByAppendingString:options[i]] : options[i];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            setMG(key, @(val));
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = cell;
        alert.popoverPresentationController.sourceRect = cell.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)onSwitch:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"key");
    BOOL inverted = sender.tag == 1;
    setMG(key, @(inverted ? !sender.on : sender.on));
}

- (void)onTextEdit:(UITextField *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"key");
    NSNumber *def = objc_getAssociatedObject(sender, @"def");
    NSInteger val = [sender.text integerValue];
    setMG(key, @(val));
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
