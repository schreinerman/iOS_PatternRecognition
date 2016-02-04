//
//  ViewController.h
//  Fm Pattern Recognition
//
//  Created by Manuel Schreiner on 25.01.16.
//  Copyright © 2016 io-expert.com. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController
@property (weak, nonatomic) IBOutlet UILabel *lblSpeed;
@property (weak, nonatomic) IBOutlet UILabel *lblStatus;

@property (weak, nonatomic) IBOutlet UIImageView *imgWheelbg;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;
@property (weak, nonatomic) IBOutlet UILabel *simMode;


@property (weak, nonatomic) IBOutlet UIView *viewMain;
@property (strong, nonatomic) IBOutlet UISwipeGestureRecognizer *swipeHandle;

- (IBAction)swipeChanged:(id)sender;
@property (weak, nonatomic) IBOutlet UIImageView *imgCursor;
@property (weak, nonatomic) IBOutlet UISlider *sldrSpeed;
@property (weak, nonatomic) IBOutlet UIImageView *imgLastFoundSymbol;
@property (weak, nonatomic) IBOutlet UIImageView *imgSymbol0;
@property (weak, nonatomic) IBOutlet UIImageView *imgSymbol1;
@property (weak, nonatomic) IBOutlet UIImageView *imgSymbol2;
@property (weak, nonatomic) IBOutlet UIImageView *imgSymbol3;
@property (weak, nonatomic) IBOutlet UIImageView *imgSymbol4;
@property (weak, nonatomic) IBOutlet UIImageView *imgSymbol5;
@property (weak, nonatomic) IBOutlet UIImageView *imgSymbol6;
@property (weak, nonatomic) IBOutlet UIImageView *imgSymbol7;
@property (weak, nonatomic) IBOutlet UIImageView *imgWheeltop;
@property (strong, nonatomic) IBOutlet UIRotationGestureRecognizer *rotHandle;

- (IBAction)btnPosTouched:(id)sender;
- (IBAction)sldrValueChanged:(id)sender;
- (IBAction)btnRelearn:(id)sender;
- (IBAction)rotDone:(id)sender;
- (IBAction)btnCaptureTouched:(id)sender;


@end

