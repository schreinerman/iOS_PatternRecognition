//
//  ViewController.m
//  Fm Pattern Recognition
//
//  Created by Manuel Schreiner on 25.01.16.
//  Copyright © 2016 io-expert.com. All rights reserved.
//

#import "ViewController.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import <AudioToolbox/AudioToolbox.h>

#define TRANSFER_SERVICE_RX_UUID           @"00000010-0000-1000-8000-00805F9B34FB"
#define TRANSFER_SERVICE_TX_UUID           @"00000000-0000-1000-8000-00805F9B34FB"
#define TRANSFER_CHARACTERISTIC_RX_UUID    @"00000011-0000-1000-8000-00805F9B34FB"
#define TRANSFER_CHARACTERISTIC_TX_UUID    @"00000001-0000-1000-8000-00805F9B34FB"

#define STATUS_DISCONNECTED              0
#define STATUS_SCAN_STARTED              1
#define STATUS_CONNECTED                 2
#define STATUS_SERVICEFOUND              4
#define STATUS_CHARACTERISTIC_FOUND      8

@interface ViewController () <CBCentralManagerDelegate, CBPeripheralDelegate>
{
    uint32_t Status;
    volatile uint32_t connectTimeout;
    int currentAngle;
    float lastRot;
    int lastRecognized;
    Boolean rotDone;
    Boolean DiscoverComplete;
    Boolean SimulatorMode;
    float SimulatorCurrentSpeed;
    float SimulatorCurrentPos;
    float SimulatorSetPos;
    Boolean SimulatorPositionMode;
    uint32_t DemoTimeout;
    int SimulatorRelearn;
}

@property (strong, nonatomic) CBCentralManager      *centralManager;
@property (strong, nonatomic) CBPeripheral          *discoveredPeripheral;
@property (strong, nonatomic) NSMutableData         *data;
@property (strong, nonatomic) CBService* TxService;
@property (strong, nonatomic) CBCharacteristic* TxCharacteristics;
@property (strong, nonatomic) CBService* RxService;
@property (strong, nonatomic) CBCharacteristic* RxCharacteristics;
@property (strong, nonatomic) NSTimer* periodicUpdateTimer;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    lastRecognized = 0;
    SimulatorMode = false;
    SimulatorCurrentSpeed = 0;
    SimulatorCurrentPos = 0;
    SimulatorSetPos = 0;
    SimulatorPositionMode = 0;
    SimulatorRelearn = -1;
    _periodicUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f/1000 target:self selector:@selector(periodUpdate) userInfo:nil repeats:YES];
    Status = STATUS_DISCONNECTED;
    connectTimeout = 5000;
    // Do any additional setup after loading the view, typically from a nib.
    _discoveredPeripheral = nil;
    _TxService = nil;
    _TxCharacteristics = nil;
    _RxService = nil;
    _RxCharacteristics = nil;
    // Start up the CBCentralManager
    _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    
    // And somewhere to store the incoming data
    _data = [[NSMutableData alloc] init];
    
    
}

-(void) periodUpdate
{
    static volatile uint32_t subcounter = 0;
    subcounter++;
    if (self.discoveredPeripheral != nil)
    {
        [self.discoveredPeripheral readRSSI];
    }
    if (SimulatorMode)
    {
        _viewMain.alpha = 1.0f;
        [self SimulatorUpdate];
        return;
    }
    if ([self communicationReady])
    {
        _viewMain.alpha = 1.0f;
    }
    else
    {
        _viewMain.alpha = .2f;
    }
    if (lastRecognized == 255)
    {
        _imgWheelbg.alpha = 0.1f;
        [_activityIndicator startAnimating];
    }
    else
    {
        _imgWheelbg.alpha = 1.0f;
        [_activityIndicator stopAnimating];
    }
    
    if (connectTimeout == 0)
    {
        _viewMain.alpha = .2f;
        if ((Status & STATUS_SCAN_STARTED) == 0)
        {
                NSLog(@"Restart scanning...");
            
                if (self.discoveredPeripheral != nil)
                {
                    [self.centralManager cancelPeripheralConnection:self.discoveredPeripheral];
                    self.discoveredPeripheral = nil;
                }
                //[self cleanup];
                connectTimeout = 5000;
            
                // We're disconnected, so start scanning again
                [self scan];
        }
        else
        {
            [self cleanup];
            [self scan];
        }
    } else
    {
        connectTimeout--;

    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    // Don't keep it going while we're not showing.
    [self.centralManager stopScan];
    NSLog(@"Scanning stopped");
    
    [super viewWillDisappear:animated];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/** Call this when things either go wrong, or you're done with the connection.
 *  This cancels any subscriptions if there are any, or straight disconnects if not.
 *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
 */
- (void)cleanup
{
    // Don't do anything if we're not connected
    if (!self.discoveredPeripheral.isAccessibilityElement) {
        return;
    }
    Status = 0;
    _TxService = nil;
    _TxCharacteristics = nil;
    _RxService = nil;
    _RxCharacteristics = nil;
    DiscoverComplete = false;
    // See if we are subscribed to a characteristic on the peripheral
    if (self.discoveredPeripheral.services != nil) {
        for (CBService *service in self.discoveredPeripheral.services) {
            if (service.characteristics != nil) {
                for (CBCharacteristic *characteristic in service.characteristics) {
                    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_RX_UUID]]) {
                        if (characteristic.isNotifying) {
                            // It is notifying, so unsubscribe
                            [self.discoveredPeripheral setNotifyValue:NO forCharacteristic:characteristic];
                            
                            // And we're done.
                            return;
                        }
                    }
                }
            }
        }
    }
    
    // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
    [self.centralManager cancelPeripheralConnection:self.discoveredPeripheral];
}


/** centralManagerDidUpdateState is a required protocol method.
 *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
 *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
 *  the Central is ready to be used.
 */
- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state != CBCentralManagerStatePoweredOn) {
        // In a real app, you'd deal with all the states correctly
        _simMode.hidden = false;
        SimulatorMode = true;
        return;
    }
    _simMode.hidden = true;
    SimulatorMode = false;
    // The state must be CBCentralManagerStatePoweredOn...
    connectTimeout = 5000;
    Status = STATUS_SCAN_STARTED | STATUS_CONNECTED;
    // ... so start scanning
    [self scan];
}

/** Scan for peripherals - specifically for our service's 128bit CBUUID
 */
- (void)scan
{
    connectTimeout = 5000;
    DiscoverComplete = false;
    Status = STATUS_SCAN_STARTED;
    [self.centralManager scanForPeripheralsWithServices:@[[CBUUID UUIDWithString:TRANSFER_SERVICE_RX_UUID],[CBUUID UUIDWithString:TRANSFER_SERVICE_TX_UUID]]
                                                options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @NO }];
    
    NSLog(@"Scanning started");
}

/** This callback comes whenever a peripheral that is advertising the TRANSFER_SERVICE_UUID is discovered.
 *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
 *  we start the connection process
 */
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    

    // Reject any where the value is above reasonable range
    NSLog(@"Discovered %@ at %@", peripheral.name, RSSI);
    
    if ((RSSI.integerValue < 0) && (RSSI.integerValue > -127)) {
        self.signalBar.progress = 1.0f * (127 + RSSI.integerValue)/127;
    }
    else
    {
        self.signalBar.progress = 0.0f;
    }
    
    if (RSSI.integerValue > 0) {
     return;
     }
    
    // Reject if the signal strength is too low to be close enough (Close is around -22dB)
    if (RSSI.integerValue < -60) {
     return;
     }
    
    connectTimeout = 5000;
    
    NSString* sName = peripheral.name;
    
    // Ok, it's in range - have we already seen it?
    if ((self.discoveredPeripheral != peripheral) && ([sName isEqualToString:@"pattern"] )){
        
        // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it
        self.discoveredPeripheral = peripheral;
        
        [self.centralManager cancelPeripheralConnection:peripheral];
        
        // And connect
        NSLog(@"Connecting to peripheral %@", peripheral);
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
}

/** If the connection fails for whatever reason, we need to deal with it.
 */
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Failed to connect to %@. (%@)", peripheral, [error localizedDescription]);
    [self cleanup];
}

/** We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
 */
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Peripheral Connected");
    connectTimeout = 5000;
    Status |= STATUS_CONNECTED;
    // Stop scanning
    [self.centralManager stopScan];
    NSLog(@"Scanning stopped");
    Status &= ~STATUS_SCAN_STARTED;
    // Clear the data that we may already have
    [self.data setLength:0];
    
    // Make sure we get the discovery callbacks
    peripheral.delegate = self;
    
    [self performSelector:@selector(delayedDiscoverServices:) withObject:peripheral afterDelay: 0.5];
    [self performSelector:@selector(delayedDiscoverServices:) withObject:peripheral afterDelay: 1];
    [self performSelector:@selector(delayedDiscoverServices:) withObject:peripheral afterDelay: 2];
    
}

-(void)delayedDiscoverServices:(CBPeripheral *)peripheral
{
    connectTimeout = 5000;
    if (peripheral.services)
    {
        [self peripheral:peripheral didDiscoverServices:nil];
    }
    else
    {
        [peripheral discoverServices:nil];
        
        // Search only for services that match our UUID
        //@[[CBUUID UUIDWithString:TRANSFER_SERVICE_TX_UUID],[CBUUID UUIDWithString:TRANSFER_SERVICE_RX_UUID]]];
        //[peripheral discoverServices] //@[[CBUUID UUIDWithString:TRANSFER_SERVICE_RX_UUID]]];
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error
{
    if ((RSSI.integerValue < 0) && (RSSI.integerValue > -127)) {
        self.signalBar.progress = 1.0f * (127 + RSSI.integerValue)/127;
    }
    else
    {
        self.signalBar.progress = 0.0f;
    }
}

/** The Transfer Service was discovered
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering services: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    connectTimeout = 5000;
    // Discover the characteristic we want...
    Status |= STATUS_SERVICEFOUND;
    
    // Loop through the newly filled peripheral.services array, just in case there's more than one.
    for (CBService *service in peripheral.services) {
        if (service.characteristics)
        {
            [self peripheral:peripheral didDiscoverCharacteristicsForService:service error:nil];
        }
        else
        {
            if ([service.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_SERVICE_TX_UUID]]) {
                [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_TX_UUID]] forService:service];
            }

            if ([service.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_SERVICE_RX_UUID]]) {
                [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_RX_UUID]] forService:service];
            }
        }
    }
}


/** The Transfer characteristic was discovered.
 *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    // Deal with errors (if any)
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    Status |= STATUS_CHARACTERISTIC_FOUND;
    _discoveredPeripheral = peripheral;
    connectTimeout = 5000;
    // Again, we loop through the array, just in case.
    NSLog(@"For Service: %@",service );
    for (CBCharacteristic *characteristic in service.characteristics) {
        // And check if it's the right one
        if ([service.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_SERVICE_RX_UUID]])
        {
            if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_RX_UUID]]) {
                _RxService = service;
                _RxCharacteristics = characteristic;
                NSLog(@"Adding RxCharacteristics: %@",_RxCharacteristics);
                // If it is, subscribe to it
                NSLog(@"Starting notification mode...");
                [peripheral setNotifyValue:YES forCharacteristic:characteristic];
            
            }
        }
        if ([service.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_SERVICE_TX_UUID]])
        {
            if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_TX_UUID]]) {
                _TxService = service;
                _TxCharacteristics = characteristic;
                NSLog(@"Adding TxCharacteristics: %@",_TxCharacteristics);
            }
        }
        
    }
    DiscoverComplete = true;
    if ([self communicationReady])
    {
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
    }
    // Once this is complete, we just need to wait for the data to come in.
}
         

/** This callback lets us know more data has arrived via notification on the characteristic
 */
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    static NSString* stringCompleteData = @"";
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        return;
    }
    NSError *json_error;
    NSString *stringFromData = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
    
    //stringCompleteData = @"";
    if (stringFromData == nil) return;
    
    stringCompleteData = [stringCompleteData stringByAppendingString:stringFromData];
    
    NSString *parseString=@"";
    NSRange searchFromRange = [stringCompleteData rangeOfString:@"{" ];
    if (searchFromRange.length > 0)
    {
        NSRange searchToRange = [stringCompleteData rangeOfString:@"}" options:0 range:NSMakeRange(searchFromRange.location,stringCompleteData.length - searchFromRange.location)];
        if (searchToRange.length > 0)
        {
            NSRange subRange = NSMakeRange(searchFromRange.location+searchFromRange.length, searchToRange.location-searchFromRange.location-searchFromRange.length);
            parseString = [stringCompleteData substringWithRange:subRange];
            subRange.location += subRange.length + 1;
            subRange.length = stringCompleteData.length - subRange.location;
            stringCompleteData = [stringCompleteData substringWithRange:subRange];
            parseString = [NSString stringWithFormat:@"{%@}",parseString];
        }
    }

    connectTimeout = 5000;
    
    /*NSRange jsonRange = NSMakeRange(1,stringCompleteData.length - 2);
    if (jsonRange.length > 0)
    {
        NSString* jsonData = [stringCompleteData substringWithRange:jsonRange];
        stringCompleteData = [NSString stringWithFormat:("{%@}",jsonData)];
    }*/
    if (parseString.length > 0)
    {
        NSData* data = [parseString dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableArray *array = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error: &json_error];
    
        [self processRxSetWheelAngle:(int)[[array valueForKey: @"ws"] integerValue]];
        
        [self processRxLastFoundSymbol:(int)[[array valueForKey: @"sf"] integerValue]];
    
        [self processRxWheelSpeed:(int)[[array valueForKey: @"wr"] integerValue]];
        
        [self processRxMotorMode:(int)[[array valueForKey: @"mm"] integerValue]];
    
        [self processRxWheelAngle:(int)[[array valueForKey: @"wa"] integerValue]];
    
        [self processRxSymbolArray:[array valueForKey: @"st"]];
    
        [self processRxStatusMessage:[array valueForKey: @"sm"]];
    
    
        //NSLog(@"Received: %@", stringFromData);
    }
}

/** Once the disconnection happens, we need to clean up our local copy of the peripheral
 */
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Peripheral Disconnected");
    self.discoveredPeripheral = nil;
    Status = 0;
    // We're disconnected, so start scanning again
    [self scan];
}


- (boolean_t)communicationReady
{
    if (DiscoverComplete == false) return false;
    if (_discoveredPeripheral == NULL) return false;
    if (_TxService == nil) return false;
    if (_TxCharacteristics == nil) return false;
    if (_RxService == nil) return false;
    if (_RxCharacteristics == nil) return false;
    return true;
}

-(void)sendString:(NSString*)strdata {
    NSData* data = [strdata dataUsingEncoding:NSUTF8StringEncoding];
    [self sendData:data];
}

-(void)sendData:(NSData*)data {
    NSString* logStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"\r\nSending: \"%@\"\r\n\r\n",logStr );
    if (_discoveredPeripheral == NULL) return;
    if (_TxCharacteristics == NULL) return;
    
    if ((_TxCharacteristics.properties & CBCharacteristicPropertyWriteWithoutResponse) != 0)
    {
        [_discoveredPeripheral writeValue:data forCharacteristic:_TxCharacteristics type:CBCharacteristicWriteWithoutResponse];
        
    }
    else
    {
        [_discoveredPeripheral writeValue:data forCharacteristic:_TxCharacteristics type:CBCharacteristicWriteWithResponse];
    }
}

- (void)peripheral:(CBPeripheral*)peripheral didWriteValueforCharacteristic:(CBCharacteristic*) characteristic error:(NSError*)error
{
    NSLog(@"Blablub %@",[error localizedDescription]);
}

- (void)processRxMotorMode:(int) mode
{
    if (mode == 1)
    {
        self.motorSwitch.on = 1;
    }
    else
    {
        self.motorSwitch.on = 0;
    }
}

- (void)processRxWheelSpeed:(int) speed
{
    _sldrSpeed.value = 1.0f * speed / 20;
    _lblSpeed.text = [NSString stringWithFormat:@"Speed: %i",(speed - 10)];
}

- (void)processRxWheelAngle:(int) angle
{
    if (angle > 359) angle %= 360;
    _imgWheeltop.transform = CGAffineTransformMakeRotation(2 * M_PI *angle / 360);
}

- (void)processRxSetWheelAngle:(int) angle
{
    if (rotDone == false)
    {
        if (angle > 359) angle %= 360;
        _imgCursor.transform = CGAffineTransformMakeRotation(2 * M_PI *angle / 360);
        _imgCursor.alpha = 1.0f;
    }
}

- (void)processRxStatusMessage:(NSString*) message
{
    _lblStatus.text = [NSString stringWithFormat:@"Status: %@",message];
}


- (void)rotateCursorTo:(int) angle
{
    currentAngle = angle;
    NSString* str = [NSString stringWithFormat:@"SetWheelSetVal=%i\r",angle];
    [self sendString:str];
}

- (void)processRxLastFoundSymbol:(int) found
{
    lastRecognized = found;
    if (lastRecognized == 255)
    {
        _imgWheelbg.alpha = 0.1f;
        [_activityIndicator startAnimating];
    }
    if (found < 10)
    {
        _imgLastFoundSymbol.image = [UIImage imageNamed:[NSString stringWithFormat:@"sym0%i.png",found]];
    }
    else if (found < 100)
    {
        _imgLastFoundSymbol.image = [UIImage imageNamed:[NSString stringWithFormat:@"sym%i.png",found]];
    } else
    {
        _imgLastFoundSymbol.image = [UIImage imageNamed:@"sym255.png"];
    }
}

- (void)processRxSymbolArray:(NSMutableArray*) symarray
{
    for(int i = 0;i < 8;i++)
    {
        int sym = (int)[symarray[i] integerValue];
        NSString* strSym;
        if (sym < 10)
        {
            strSym = [NSString stringWithFormat:@"sym0%i.png",sym];
        }
        else if (sym == 255)
        {
            strSym = @"sym255.png";
        }
        switch(i)
        {
            case 0:
                _imgSymbol0.image = [UIImage imageNamed:strSym];
                break;
            case 1:
                _imgSymbol1.image = [UIImage imageNamed:strSym];
                break;
            case 2:
                _imgSymbol2.image = [UIImage imageNamed:strSym];
                break;
            case 3:
                _imgSymbol3.image = [UIImage imageNamed:strSym];
                break;
            case 4:
                _imgSymbol4.image = [UIImage imageNamed:strSym];
                break;
            case 5:
                _imgSymbol5.image = [UIImage imageNamed:strSym];
                break;
            case 6:
                _imgSymbol6.image = [UIImage imageNamed:strSym];
                break;
            case 7:
                _imgSymbol7.image = [UIImage imageNamed:strSym];
                break;
        }
    }
}

- (void)processRxSymbolAt:(int)i forSymbol:(int)sym
{
        NSString* strSym;
        if (sym < 10)
        {
            strSym = [NSString stringWithFormat:@"sym0%i.png",sym];
        }
        else if (sym == 255)
        {
            strSym = @"sym255.png";
        }
        switch(i)
        {
            case 0:
                _imgSymbol0.image = [UIImage imageNamed:strSym];
                break;
            case 1:
                _imgSymbol1.image = [UIImage imageNamed:strSym];
                break;
            case 2:
                _imgSymbol2.image = [UIImage imageNamed:strSym];
                break;
            case 3:
                _imgSymbol3.image = [UIImage imageNamed:strSym];
                break;
            case 4:
                _imgSymbol4.image = [UIImage imageNamed:strSym];
                break;
            case 5:
                _imgSymbol5.image = [UIImage imageNamed:strSym];
                break;
            case 6:
                _imgSymbol6.image = [UIImage imageNamed:strSym];
                break;
            case 7:
                _imgSymbol7.image = [UIImage imageNamed:strSym];
                break;
        }
}

- (IBAction)btnPosTouched:(id)sender {
    UIButton * PressedButton = (UIButton*)sender;
    int pos = (int)(PressedButton.tag * 45);
    if (SimulatorMode)
    {
        [self simulatorSetPos:pos];
    }
    else
    {
        [self rotateCursorTo:pos];
    }
}

- (IBAction)sldrValueChanged:(id)sender {
    int val = (int)(_sldrSpeed.value * 20);
    NSString* str = [NSString stringWithFormat:@"SetWheelSpeed=%i\r",val];
    if (SimulatorMode)
    {
        [self simulatorSetSpeed:val];
    }
    else
    {
        [self sendString:str];
    }
}

- (IBAction)btnRelearn:(id)sender {
    if (SimulatorMode)
    {
        [self simulatorStartRelearn];
    }
    else
    {
        [self sendString:@"SetRelearn=1\r"];
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    lastRot = 0;
    rotDone = false;
}


- (IBAction)rotDone:(id)sender {
    
    float thisfloat = _rotHandle.rotation;
    if (rotDone == false)
    {
        rotDone = true;
        //[self sendString:@"sp_max=200\r"];
        //[self sendString:@"sp_max=200\r"];
        
    }
    currentAngle += 360 * (thisfloat - lastRot) / (2* M_PI);
    if (currentAngle < 0) currentAngle += 360;
    if (currentAngle > 360) currentAngle -= 360;
    lastRot = thisfloat;
    
    if (currentAngle > 359) currentAngle %= 360;
    _imgCursor.transform = CGAffineTransformMakeRotation(2 * M_PI *currentAngle / 360);
    _imgCursor.alpha = .5f;
    if (_rotHandle.state == UIGestureRecognizerStateEnded)
    {
        _imgCursor.alpha = 1.0f;
        if (SimulatorMode)
        {
            [self simulatorSetPos:currentAngle];
        }
        else
        {
            [self rotateCursorTo:currentAngle];
        }
        rotDone = false;
    }
    
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    lastRot = 0;
    rotDone = false;
}

- (IBAction)btnCaptureTouched:(id)sender {
    [self sendString:@"capture\r"];
}





- (IBAction)motorSwitchTouched:(id)sender {
    [self sendString:[NSString stringWithFormat:@"SetMode=%i\r",self.motorSwitch.on]];
}

- (IBAction)swipeChanged:(id)sender {
    if (_swipeHandle.direction == UISwipeGestureRecognizerDirectionRight)
    {
        if (_sldrSpeed.value < 0.9f)
        {
        _sldrSpeed.value += 0.1f;
        }
    }
    if (_swipeHandle.direction == UISwipeGestureRecognizerDirectionLeft)
    {
        if (_sldrSpeed.value > 0.0f)
        {
            _sldrSpeed.value -= 0.1f;
        }
    }
}

// *******************************************
//                  Simulator
// *******************************************

-(void) SimulatorUpdate
{
    static int symbolCache[8];
    static Boolean PosReached = false;
    if (DemoTimeout > 0) DemoTimeout--;
    
    if (SimulatorPositionMode)
    {
        if (abs((int)(SimulatorCurrentPos - SimulatorSetPos)) == 0)
        {
            SimulatorCurrentPos = SimulatorSetPos;
        }
        
        if (SimulatorCurrentPos == SimulatorSetPos)
        {
            if ((PosReached == true) && ((((int)SimulatorCurrentPos) % 45) == 0) && ((SimulatorRelearn == 0) ))
            {
                PosReached = false;
            }
            if ((PosReached == false) && ((((int)SimulatorCurrentPos) % 45) == 0))
            {
                symbolCache[(int)SimulatorCurrentPos/45] = arc4random_uniform(8);
                PosReached = true;
                [self processRxSymbolAt:(int)SimulatorCurrentPos/45 forSymbol:symbolCache[(int)SimulatorCurrentPos/45]];
                [self processRxLastFoundSymbol:symbolCache[(int)SimulatorCurrentPos/45]];
                if ((SimulatorRelearn >= 0) && (SimulatorRelearn < 8))
                {
                    SimulatorRelearn++;
                    [self performSelector:@selector(nextRelearnPos)  withObject:nil afterDelay:0.5];
                }
            }
        }
        else if (((SimulatorCurrentPos < SimulatorSetPos) && ((SimulatorSetPos - SimulatorCurrentPos) < 180)) || ((SimulatorCurrentPos > SimulatorSetPos) && ((SimulatorCurrentPos - SimulatorSetPos) > 180)))
        {
            PosReached = false;
            SimulatorCurrentPos += 0.1f;
        } else
        {
            PosReached = false;
            SimulatorCurrentPos -= 0.1f;
        }
    }
    else
    {
        PosReached = false;
        SimulatorCurrentPos += SimulatorCurrentSpeed;
        SimulatorSetPos = SimulatorCurrentPos;
        [self processRxSetWheelAngle:(int)SimulatorCurrentPos];
    }
    
    while(SimulatorSetPos >= 360)
    {
        SimulatorSetPos -= 360;
    }
    while(SimulatorSetPos < 0)
    {
        SimulatorSetPos = 360 + SimulatorSetPos;
    }

    
    while(SimulatorCurrentPos >= 360)
    {
        SimulatorCurrentPos -= 360;
    }
    while(SimulatorCurrentPos < 0)
    {
        SimulatorCurrentPos = 360 + SimulatorCurrentPos;
    }
    [self processRxWheelAngle:(int)SimulatorCurrentPos];
}

-(void)nextRelearnPos
{
    [self simulatorSetPos: (int)SimulatorRelearn*45];
}

-(void)simulatorSetPos:(int)pos
{
    DemoTimeout = 15000;
    SimulatorSetPos = pos;
    SimulatorPositionMode = true;
    [self processRxSetWheelAngle:pos];
}

-(void)simulatorSetSpeed:(int)speed
{
    DemoTimeout = 15000;
    SimulatorPositionMode = false;
    SimulatorCurrentSpeed = 0.1f * (speed-10);
}
-(void)simulatorStartRelearn
{
    for(int i = 0;i< 8;i++)
    {
        [self processRxSymbolAt:i forSymbol:0];
    }
    SimulatorRelearn = 0;
    [self simulatorSetPos:0];
}


/*
 UIActionSheet *popup = [[UIActionSheet alloc] initWithTitle:@"Connect to:" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:
 @"Pattern",
 @"Serial Bridge",
 @"Demeter",
 nil];
 UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
 handler:^(UIAlertAction * action) {}];
 [popup addButtonWithTitle:@"Pattern2"];
 
 popup.tag = 1;
 [popup showInView:self.view];

 
- (void)actionSheet:(UIActionSheet *)popup clickedButtonAtIndex:(NSInteger)buttonIndex {
 
       NSString *buttonTitle = [popup buttonTitleAtIndex:buttonIndex];
    NSLog(buttonTitle);
    
    
    }
 */

@end
