//
//  MasterViewController.h
//  OCS iPad Examples
//
//  Created by Aurelius Prochazka on 8/10/12.
//  Copyright (c) 2012 Hear For Yourself. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DetailViewController;

@interface MasterViewController : UITableViewController

@property (strong, nonatomic) DetailViewController *detailViewController;

@end
