// Copyright 2017 Google Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "ViewController.h"
#import <ModelIO/ModelIO.h>
#import <SceneKit/SceneKit.h>
#import <SceneKit/ModelIO.h>

// IMPORTANT: replace this with your project's API key.
static NSString * const POLY_API_KEY = @"YOUR API KEY";
static NSString * const POLY_BASE_GET_ASSET_URL = @"https://poly.googleapis.com/v1/assets";
static NSString * const POLY_ASSET_ID = @"5vbJ5vildOq";

@interface ViewController () <ARSCNViewDelegate, NSURLSessionDownloadDelegate>

@property (nonatomic, strong) IBOutlet ARSCNView *sceneView;

// A string of web URLs of files to download locally.
@property (nonatomic, strong) NSMutableArray *fileURLsToDownload;

// Local path to obj file.
@property (nonatomic, strong) NSURL *objPathURL;

// Local path to mtl file
@property (nonatomic, strong) NSURL *mtlPathURL;

// Keep track of total number of files downloaded.
@property (nonatomic) NSInteger totalFilesDownloaded;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Set the view's delegate
    self.sceneView.delegate = self;
    
    // Show statistics such as fps and timing information
    self.sceneView.showsStatistics = YES;
    
    // Set the view's delegate. We don't make a lot of use of that now; if we did plane detection,
    // though, this is how we'd get notified about events from ARKit.
    self.sceneView.delegate = self;
    
    // Provide some nice defaults to the scene.
    self.sceneView.autoenablesDefaultLighting = YES;
    self.sceneView.automaticallyUpdatesLighting = YES;
    
    // Set total files downloaded to zero.
    self.totalFilesDownloaded = 0;
    
    // Get our json from poly API.
    [self getObjectFromPoly];
    
    // Download necessary files.
    [self downloadFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Create a session configuration
    ARWorldTrackingConfiguration *configuration = [ARWorldTrackingConfiguration new];

    // Run the view's session
    [self.sceneView.session runWithConfiguration:configuration];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Pause the view's session
    [self.sceneView.session pause];
}

- (void)getObjectFromPoly {
    self.fileURLsToDownload = [NSMutableArray array];

    NSString *polyURLWithKey = [NSString stringWithFormat:@"%@/%@?key=%@", POLY_BASE_GET_ASSET_URL, POLY_ASSET_ID , POLY_API_KEY];
    NSURL *polyURL = [NSURL URLWithString:polyURLWithKey];
    NSError *error;
    NSData *data = [NSData dataWithContentsOfURL:polyURL];
    NSMutableArray *json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
    
    if (!error) {
        // If there are no errors, parse our json to retrieve URLs to download.
        NSMutableArray *formats = [json valueForKey:@"formats"];
        NSMutableDictionary *format = [formats objectAtIndex:0];
        NSMutableDictionary *root = [format valueForKey:@"root"];
        NSMutableArray *resources = [format valueForKey:@"resources"];
        NSMutableDictionary *resource = [resources objectAtIndex:0];
        
        [self.fileURLsToDownload addObject:[root valueForKey:@"url"]];
        [self.fileURLsToDownload addObject:[resource valueForKey:@"url"]];
        
    } else {
        NSLog(@"Failed to connect to Poly. %@", [error localizedDescription]);
    }
}

- (void)downloadFiles {
    // Async download files.
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    for (NSString *fileURL in self.fileURLsToDownload) {
        NSURL *url = [NSURL URLWithString:fileURL];
        NSURLSessionTask *downloadTask = [session downloadTaskWithURL:url];
        [downloadTask resume];
    }
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *finalPath = [documentsPath stringByAppendingPathComponent:[[[downloadTask originalRequest] URL] lastPathComponent]];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    BOOL success;
    NSError *error;
    if ([fileManager fileExistsAtPath:finalPath]) {
        success = [fileManager removeItemAtPath:finalPath error:&error];
        NSAssert(success, @"removeItemAtPath error: %@", error);
    }
    
    NSURL *finalPathURL = [NSURL fileURLWithPath:finalPath];
    success = [fileManager moveItemAtURL:location toURL:finalPathURL error:&error];
    
    if (success) {
        self.totalFilesDownloaded++;
        if ([[finalPathURL lastPathComponent] containsString:@"obj"]) {
            self.objPathURL = finalPathURL;
        } else if ([[finalPathURL lastPathComponent] containsString:@"mtl"]) {
            self.mtlPathURL = finalPathURL;
        }
        
        // If we've downloaded both files, let's add the asset to our scene.
        if (self.totalFilesDownloaded == 2) {
            [self loadObjectToScene];
        }
        
        NSAssert(success, @"moveItemAtURL error: %@", error);
    } else {
        NSLog(@"Failed to download file. %@", [error localizedDescription]);
    }
}

- (void)loadObjectToScene {
    MDLAsset *mdlAsset = [[MDLAsset alloc] initWithURL:self.objPathURL];
    [mdlAsset loadTextures];
    SCNNode *node = [SCNNode nodeWithMDLObject:[mdlAsset objectAtIndex:0]];
    node.scale = SCNVector3Make(.15, .15, .15);
    node.position = SCNVector3Make(0, -.2, -.8);
    
    SCNAction *rotate =
    [SCNAction repeatActionForever:[SCNAction rotateByAngle:M_PI aroundAxis:SCNVector3Make(0, 1, 0) duration:3]];
    [node runAction:rotate];
    
    [self.sceneView.scene.rootNode addChildNode:node];
}

@end
