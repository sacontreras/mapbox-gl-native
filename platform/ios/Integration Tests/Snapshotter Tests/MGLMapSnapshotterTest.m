#import "MGLMapViewIntegrationTest.h"

@interface MGLMapSnapshotterTest : MGLMapViewIntegrationTest
@end

// Convenience func to create snapshotter
MGLMapSnapshotter* snapshotterWithCoordinates(CLLocationCoordinate2D coordinates, CGSize size) {
    // Create snapshot options
    MGLMapCamera* mapCamera    = [[MGLMapCamera alloc] init];
    mapCamera.pitch            = 20;
    mapCamera.centerCoordinate = coordinates;
    MGLMapSnapshotOptions* options = [[MGLMapSnapshotOptions alloc] initWithStyleURL:[MGLStyle satelliteStreetsStyleURL]
                                                                              camera:mapCamera
                                                                                size:size];
    options.zoomLevel = 10;

    // Create and start the snapshotter
    MGLMapSnapshotter* snapshotter = [[MGLMapSnapshotter alloc] initWithOptions:options];
    return snapshotter;
}

NSString* validAccessToken() {
    NSString *accessToken = [[NSProcessInfo processInfo] environment][@"MAPBOX_ACCESS_TOKEN"];
    if (!accessToken) {
        printf("warning: MAPBOX_ACCESS_TOKEN env var is required for this test - skipping.\n");
        return nil;
    }

    [MGLAccountManager setAccessToken:accessToken];
    return accessToken;
}

@implementation MGLMapSnapshotterTest

- (void)testMultipleSnapshotsWithASingleSnapshotter {
    if (!validAccessToken()) {
        return;
    }

    CGSize size = self.mapView.bounds.size;

    XCTestExpectation *expectation = [self expectationWithDescription:@"snapshots"];
    expectation.expectedFulfillmentCount = 2;
    expectation.assertForOverFulfill = YES;

    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(30.0, 30.0);

    MGLMapSnapshotter *snapshotter = snapshotterWithCoordinates(coord, size);
    XCTAssertNotNil(snapshotter);

    [snapshotter startWithCompletionHandler:^(MGLMapSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        [expectation fulfill];
    }];

    @try {
        [snapshotter startWithCompletionHandler:^(MGLMapSnapshot * _Nullable snapshot, NSError * _Nullable error) {
            XCTFail(@"Should not be called - but should it?");
        }];
        XCTFail(@"Should not be called");
    }
    @catch (NSException *exception) {
        XCTAssert(exception.name == NSInternalInconsistencyException);
        [expectation fulfill];
    }

    [self waitForExpectations:@[expectation] timeout:10.0];
}

- (void)testAllocatingSnapshotOnBackgroundQueue {
    if (!validAccessToken()) {
        return;
    }

    XCTestExpectation *expectation = [self expectationWithDescription:@"snapshots"];

    CGSize size                  = self.mapView.bounds.size;
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(30.0, 30.0);

    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, QOS_MIN_RELATIVE_PRIORITY);
    dispatch_queue_t backgroundQueue = dispatch_queue_create(__PRETTY_FUNCTION__, attr);

    // This crashes maybe 1 in 10 times.
    dispatch_async(backgroundQueue, ^{

        // Create the snapshotter - DO NOT START.
        MGLMapSnapshotter* snapshotter = snapshotterWithCoordinates(coord, size);

        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            dispatch_group_leave(group);
        });

        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        snapshotter = nil;

        dispatch_sync(dispatch_get_main_queue(), ^{
            [expectation fulfill];
        });
    });

    [self waitForExpectations:@[expectation] timeout:2.0];
}

- (void)testMultipleSnapshottersFromBackgroundQueue {
    if (!validAccessToken()) {
        return;
    }

    // Crashes with only 1 snapshot
    CGSize size = self.mapView.bounds.size;
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(30.0, 30.0);

    XCTestExpectation *expectation = [self expectationWithDescription:@"snapshots"];
    expectation.expectedFulfillmentCount = 1;
    expectation.assertForOverFulfill = YES;

    __weak __typeof__(self) weakself = self;

    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, QOS_MIN_RELATIVE_PRIORITY); // also for concurrent
    dispatch_queue_t backgroundQueue = dispatch_queue_create(__PRETTY_FUNCTION__, attr);


    // Use dispatch_group to keep the backgroundQueue block around (and
    // so also the MGLMapSnapshotter
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);


    dispatch_async(backgroundQueue, ^{

        MGLMapSnapshotter *snapshotter = snapshotterWithCoordinates(coord, size);
        XCTAssertNotNil(snapshotter);

        MGLMapSnapshotCompletionHandler completion = ^(MGLMapSnapshot * _Nullable snapshot, NSError * _Nullable error) {

            // This should be the main queue
            __typeof__(self) strongself = weakself;

            MGLTestAssertNotNil(strongself, strongself);

            MGLTestAssertNotNil(strongself, snapshot);
            MGLTestAssertNotNil(strongself, snapshot.image);
            MGLTestAssertNil(strongself, error, @"Snapshot should not error with: %@", error);

            // Change this back to XCTAttachmentLifetimeDeleteOnSuccess when we're sure this
            // test is passing.
            XCTAttachment *attachment = [XCTAttachment attachmentWithImage:snapshot.image];
            attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
            [strongself addAttachment:attachment];

            dispatch_group_leave(group);
        };

        // untested
        @try {
            [snapshotter startWithCompletionHandler:completion];
            MGLTestFailWithSelf(weakself);
        }
        @catch (NSException *exception) {
            MGLTestAssert(weakself, exception.name == NSInvalidArgumentException);
            dispatch_group_leave(group);
        }

        // Wait for the snapshot to complete
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        snapshotter = nil;

        dispatch_sync(dispatch_get_main_queue(), ^{
            [expectation fulfill];
        });
    });

    [self waitForExpectations:@[expectation] timeout:10.0];
}

- (void)testMultipleSnapshotters {
    if (!validAccessToken()) {
        return;
    }

    NSUInteger numSnapshots = 8;
    CGSize size = self.mapView.bounds.size;

    XCTestExpectation *expectation = [self expectationWithDescription:@"snapshots"];
    expectation.expectedFulfillmentCount = numSnapshots;
    expectation.assertForOverFulfill = YES;

    __weak __typeof__(self) weakself = self;

    for (size_t run = 0; run < numSnapshots; run++) {

        float ratio = (float)run/(float)numSnapshots;
        float latlon = (ratio*30.0) + ((1-ratio)*40.0);
        CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(latlon, latlon);

        MGLMapSnapshotter *snapshotter = snapshotterWithCoordinates(coord, size);
        XCTAssertNotNil(snapshotter);

        [snapshotter startWithCompletionHandler:^(MGLMapSnapshot * _Nullable snapshot, NSError * _Nullable error) {

            // This should be the main queue
            __typeof__(self) strongself = weakself;

            MGLTestAssertNotNil(strongself, strongself);

            MGLTestAssertNotNil(strongself, snapshot);
            MGLTestAssertNotNil(strongself, snapshot.image);
            MGLTestAssertNil(strongself, error, @"Snapshot should not error with: %@", error);

            // Change this back to XCTAttachmentLifetimeDeleteOnSuccess when we're sure this
            // test is passing.
            XCTAttachment *attachment = [XCTAttachment attachmentWithImage:snapshot.image];
            attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
            [strongself addAttachment:attachment];
            [expectation fulfill];
        }];
    } // end for loop

    [self waitForExpectations:@[expectation] timeout:20.0];
}

@end
