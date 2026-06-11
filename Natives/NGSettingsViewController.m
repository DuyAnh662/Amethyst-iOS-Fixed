#import "NGSettingsViewController.h"
#import "LauncherPreferences.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import <objc/runtime.h>

@interface NGSettingsViewController () <UIPickerViewDataSource, UIPickerViewDelegate>

@property(nonatomic) NSArray *sectionItems;
@property(nonatomic) UIPickerView *pickerView;
@property(nonatomic) UITextField *activeField;

@end

static NSString *ngKey(NSString *key) {
    return [NSString stringWithFormat:@"ng.%@", key];
}

static NSInteger ngInt(NSString *key, NSInteger def) {
    id val = getPrefObject(ngKey(key));
    return val ? [val integerValue] : def;
}

static float ngFloat(NSString *key, float def) {
    id val = getPrefObject(ngKey(key));
    return val ? [val floatValue] : def;
}

static BOOL ngBool(NSString *key, BOOL def) {
    id val = getPrefObject(ngKey(key));
    return val ? [val boolValue] : def;
}

static void setNG(NSString *key, id value) {
    setPrefObject(ngKey(key), value);
}

typedef NS_ENUM(NSInteger, NGCellType) {
    NGCellSwitch,
    NGCellPicker,
    NGCellTextField,
    NGCellSlider
};

@implementation NGSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"NG-GL4ES";

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;

    self.sectionItems = @[
        // Section 0: Basic
        @[
            @{@"key": @"nobanner", @"label": @"Disable Banner", @"desc": @"Suppress the NG-GL4ES startup banner",
              @"type": @(NGCellSwitch), @"def": @NO},
            @{@"key": @"noerror", @"label": @"No Error", @"desc": @"glGetError() always returns GL_NOERROR",
              @"type": @(NGCellSwitch), @"def": @NO},
            @{@"key": @"showfps", @"label": @"Show FPS", @"desc": @"Display FPS counter",
              @"type": @(NGCellSwitch), @"def": @NO},
            @{@"key": @"vsync", @"label": @"VSync", @"desc": @"Enable vertical sync",
              @"type": @(NGCellSwitch), @"def": @YES},
            @{@"key": @"normalize", @"label": @"Normalize", @"desc": @"Normalize colors (fix white sheep/banner)",
              @"type": @(NGCellSwitch), @"def": @YES},
        ],
        // Section 1: Rendering
        @[
            @{@"key": @"batchMode", @"label": @"Batch Mode", @"desc": @"Set batching mode for draw calls",
              @"type": @(NGCellPicker),
              @"options": @[@"Disabled", @"Auto", @"1 (small)", @"2 (medium)", @"3 (large)"],
              @"values": @[@0, @-1, @1, @2, @3], @"def": @-1},
            @{@"key": @"esVersion", @"label": @"OpenGL ES Version", @"desc": @"Target ES version",
              @"type": @(NGCellPicker),
              @"options": @[@"Auto", @"ES 2.0", @"ES 3.0"],
              @"values": @[@0, @2, @3], @"def": @0},
            @{@"key": @"glVersion", @"label": @"Reported GL Version", @"desc": @"Override reported OpenGL version",
              @"type": @(NGCellPicker),
              @"options": @[@"Auto", @"GL 2.1", @"GL 3.0", @"GL 3.3", @"GL 4.1", @"GL 4.5"],
              @"values": @[@0, @21, @30, @33, @41, @45], @"def": @0},
            @{@"key": @"fboMode", @"label": @"FBO Mode", @"desc": @"Framebuffer object handling",
              @"type": @(NGCellPicker),
              @"options": @[@"Auto", @"Disabled", @"Readback", @"Blit", @"Texture blit"],
              @"values": @[@0, @1, @2, @3, @4], @"def": @0},
            @{@"key": @"streamMode", @"label": @"Texture Streaming", @"desc": @"Texture streaming mode",
              @"type": @(NGCellPicker),
              @"options": @[@"Disabled", @"Low", @"Medium", @"High", @"Auto"],
              @"values": @[@0, @1, @2, @3, @-1], @"def": @-1},
        ],
        // Section 2: Texture
        @[
            @{@"key": @"texshrink", @"label": @"Texture Shrink", @"desc": @"Shrink textures by factor (0 = disabled)",
              @"type": @(NGCellPicker),
              @"options": @[@"Disabled", @"2x", @"4x", @"8x"],
              @"values": @[@0, @1, @2, @3], @"def": @0},
            @{@"key": @"gamma", @"label": @"Gamma Correction", @"desc": @"Gamma value (0.0 = disabled)",
              @"type": @(NGCellTextField), @"def": @0, @"placeholder": @"0.0"},
        ],
        // Section 3: Features
        @[
            @{@"key": @"nointovlhack", @"label": @"No Overload Hack", @"desc": @"Disable overloaded functions hack (needed for 1.17+)",
              @"type": @(NGCellSwitch), @"def": @YES},
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
        case 0: return @"Basic";
        case 1: return @"Rendering";
        case 2: return @"Texture";
        case 3: return @"Features";
        default: return @"";
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.sectionItems[section] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.sectionItems[indexPath.section][indexPath.row];
    NSString *key = item[@"key"];
    NGCellType type = [item[@"type"] integerValue];

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
        case NGCellSwitch: {
            UISwitch *sw = [[UISwitch alloc] init];
            BOOL val = ngBool(key, [item[@"def"] boolValue]);
            sw.on = val;
            [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
            objc_setAssociatedObject(sw, @"key", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case NGCellPicker: {
            NSInteger val = ngInt(key, [item[@"def"] integerValue]);
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
        case NGCellTextField: {
            NSInteger val = ngInt(key, [item[@"def"] integerValue]);
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
        case NGCellSlider: {
            float val = ngFloat(key, [item[@"def"] floatValue]);
            cell.detailTextLabel.text = item[@"desc"];
            // Use a simple label showing value, the actual slider is in the picker
            UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];
            vl.text = [NSString stringWithFormat:@"%.1f", val];
            vl.textAlignment = NSTextAlignmentRight;
            vl.textColor = self.view.tintColor;
            vl.font = [UIFont systemFontOfSize:14];
            cell.accessoryView = vl;
            break;
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *item = self.sectionItems[indexPath.section][indexPath.row];
    NGCellType type = [item[@"type"] integerValue];
    if (type != NGCellPicker) return;

    NSString *key = item[@"key"];
    UIView *cell = [tableView cellForRowAtIndexPath:indexPath];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item[@"label"]
        message:item[@"desc"] preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *options = item[@"options"];
    NSArray *values = item[@"values"];
    NSInteger cur = ngInt(key, [item[@"def"] integerValue]);

    for (NSInteger i = 0; i < options.count; i++) {
        NSInteger val = [values[i] integerValue];
        NSString *title = (val == cur) ? [@"✓ " stringByAppendingString:options[i]] : options[i];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            setNG(key, @(val));
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
    setNG(key, @(sender.on));
}

- (void)onTextEdit:(UITextField *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"key");
    NSNumber *def = objc_getAssociatedObject(sender, @"def");
    NSInteger val = [sender.text integerValue];
    setNG(key, @(val));
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
