#import "MGSettingsViewController.h"
#import "LauncherPreferences.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface MGSettingsViewController () <UIPickerViewDataSource, UIPickerViewDelegate>

@property(nonatomic) NSArray *sections;
@property(nonatomic) NSArray *sectionItems;
@property(nonatomic) UIPickerView *pickerView;
@property(nonatomic) UITextField *activeField;

@end

static NSString *mgPref(NSString *key) {
    return [NSString stringWithFormat:@"mg.%@", key];
}

static NSInteger mgIntPref(NSString *key, NSInteger def) {
    id val = getPrefObject(mgPref(key));
    return val ? [val integerValue] : def;
}

static BOOL mgBoolPref(NSString *key, BOOL def) {
    id val = getPrefObject(mgPref(key));
    return val ? [val boolValue] : def;
}

static void setMgPref(NSString *key, id value) {
    setPrefObject(mgPref(key), value);
}

@implementation MGSettingsViewController

typedef NS_ENUM(NSInteger, MGSettingType) {
    MGSettingTypeSwitch,
    MGSettingTypePicker,
    MGSettingTypeTextField
};

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileGlues Settings";
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    
    self.sections = @[
        localize(@"mg.section.rendering", nil),
        localize(@"mg.section.extensions", nil),
        localize(@"mg.section.performance", nil),
        localize(@"mg.section.advanced", nil)
    ];
    
    self.sectionItems = @[
        // Rendering section
        @[
            @{@"key": @"enableAngle", @"label": @"Enable ANGLE", @"desc": @"Use ANGLE for OpenGL ES translation",
              @"type": @(MGSettingTypePicker), @"options": @[@"DisableIfPossible", @"EnableIfPossible", @"ForceDisable", @"ForceEnable"],
              @"values": @[@0, @1, @2, @3], @"def": @0},
            @{@"key": @"ignoreError", @"label": @"Error Ignoring", @"desc": @"Suppress OpenGL error checking",
              @"type": @(MGSettingTypePicker), @"options": @[@"Auto/None", @"Disable", @"Level1 (Partial)", @"Level2 (Full)"],
              @"values": @[@0, @1, @2, @3], @"def": @1},
            @{@"key": @"customGLVersion", @"label": @"OpenGL Version", @"desc": @"Custom GL version override (32-46)",
              @"type": @(MGSettingTypePicker), @"options": @[@"Default (4.0)", @"3.2", @"3.3", @"4.0", @"4.1", @"4.2", @"4.3", @"4.4", @"4.5", @"4.6"],
              @"values": @[@0, @32, @33, @40, @41, @42, @43, @44, @45, @46], @"def": @0},
        ],
        // Extensions section
        @[
            @{@"key": @"extComputeShader", @"label": @"Compute Shader", @"desc": @"ARB_compute_shader extension (experimental)",
              @"type": @(MGSettingTypeSwitch), @"def": @NO},
            @{@"key": @"extTimerQuery", @"label": @"Timer Query", @"desc": @"Enable timer query extension",
              @"type": @(MGSettingTypeSwitch), @"def": @NO},
            @{@"key": @"extDirectStateAccess", @"label": @"Direct State Access", @"desc": @"Enable DSA (direct_state_access) extension",
              @"type": @(MGSettingTypeSwitch), @"def": @YES},
            @{@"key": @"hideMGEnv", @"label": @"Hide MG Environment", @"desc": @"Hide MG extensions and randomize GL strings",
              @"type": @(MGSettingTypeSwitch), @"def": @NO},
        ],
        // Performance section
        @[
            @{@"key": @"fsr1Setting", @"label": @"FSR Upscaling", @"desc": @"AMD FSR 1.0 upscaling quality",
              @"type": @(MGSettingTypePicker), @"options": @[@"Disabled", @"Ultra Quality", @"Quality", @"Balanced", @"Performance"],
              @"values": @[@0, @1, @2, @3, @4], @"def": @0},
            @{@"key": @"multidrawMode", @"label": @"Multi-Draw Mode", @"desc": @"Multi-draw emulation strategy",
              @"type": @(MGSettingTypePicker), @"options": @[@"Auto", @"PreferIndirect", @"PreferBaseVertex", @"PreferMultidrawIndirect", @"DrawElements", @"Compute"],
              @"values": @[@0, @1, @2, @3, @4, @5], @"def": @0},
            @{@"key": @"maxGlslCacheSize", @"label": @"GLSL Cache (MB)", @"desc": @"Shader cache size in MB (-1 to disable)",
              @"type": @(MGSettingTypeTextField), @"def": @30},
        ],
        // Advanced section
        @[
            @{@"key": @"angleDepthClearFix", @"label": @"ANGLE Depth Clear Fix", @"desc": @"Fix depth clearing on ANGLE",
              @"type": @(MGSettingTypePicker), @"options": @[@"Disabled", @"Mode 1", @"Mode 2"],
              @"values": @[@0, @1, @2], @"def": @0},
        ]
    ];
    
    self.pickerView = [[UIPickerView alloc] init];
    self.pickerView.delegate = self;
    self.pickerView.dataSource = self;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"Done", nil)
        style:UIBarButtonItemStyleDone target:self action:@selector(dismissView)];
}

- (void)dismissView {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.sectionItems[section] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.sectionItems[indexPath.section][indexPath.row];
    NSString *key = item[@"key"];
    MGSettingType type = [item[@"type"] integerValue];
    
    NSString *cellId = [NSString stringWithFormat:@"cell_%ld_%ld", (long)indexPath.section, (long)indexPath.row];
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
        case MGSettingTypeSwitch: {
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = mgBoolPref(key, [item[@"def"] boolValue]);
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            objc_setAssociatedObject(sw, @"key", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case MGSettingTypePicker: {
            NSInteger val = mgIntPref(key, [item[@"def"] integerValue]);
            NSArray *values = item[@"values"];
            NSArray *options = item[@"options"];
            NSInteger idx = [values indexOfObject:@(val)];
            if (idx == NSNotFound) idx = 0;
            cell.detailTextLabel.text = item[@"desc"];
            
            UILabel *valLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 120, 30)];
            valLabel.text = options[idx];
            valLabel.textAlignment = NSTextAlignmentRight;
            valLabel.textColor = self.view.tintColor;
            valLabel.font = [UIFont systemFontOfSize:15];
            cell.accessoryView = valLabel;
            break;
        }
        case MGSettingTypeTextField: {
            NSInteger val = mgIntPref(key, [item[@"def"] integerValue]);
            UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 80, 30)];
            tf.text = [NSString stringWithFormat:@"%ld", (long)val];
            tf.textAlignment = NSTextAlignmentRight;
            tf.keyboardType = UIKeyboardTypeNumberPad;
            tf.borderStyle = UITextBorderStyleRoundedRect;
            tf.delegate = self;
            objc_setAssociatedObject(tf, @"key", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [tf addTarget:self action:@selector(textFieldChanged:) forControlEvents:UIControlEventEditingDidEnd];
            cell.accessoryView = tf;
            break;
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *item = self.sectionItems[indexPath.section][indexPath.row];
    MGSettingType type = [item[@"type"] integerValue];
    
    if (type == MGSettingTypePicker) {
        NSString *key = item[@"key"];
        UIView *cell = [tableView cellForRowAtIndexPath:indexPath];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:item[@"label"]
            message:item[@"desc"] preferredStyle:UIAlertControllerStyleActionSheet];
        
        NSArray *options = item[@"options"];
        NSArray *values = item[@"values"];
        NSInteger currentVal = mgIntPref(key, [item[@"def"] integerValue]);
        
        for (NSInteger i = 0; i < options.count; i++) {
            NSInteger val = [values[i] integerValue];
            NSString *title = options[i];
            if (val == currentVal) {
                title = [NSString stringWithFormat:@"✓ %@", title];
            }
            [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                setMgPref(key, @(val));
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
}

#pragma mark - Switch handler

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"key");
    setMgPref(key, @(sender.on));
}

#pragma mark - TextField

- (void)textFieldDidEndEditing:(UITextField *)textField {
    NSString *key = objc_getAssociatedObject(textField, @"key");
    NSInteger val = [textField.text integerValue];
    setMgPref(key, @(val));
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Picker View

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return 0;
}

@end
