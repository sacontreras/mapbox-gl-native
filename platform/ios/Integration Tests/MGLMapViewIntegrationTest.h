#import <XCTest/XCTest.h>
#import <Mapbox/Mapbox.h>

#define MGLTestFailWithSelf(myself, ...) \
    _XCTPrimitiveFail(myself, __VA_ARGS__)

#define MGLTestAssert(myself, expression, ...) \
    _XCTPrimitiveAssertTrue(myself, expression, @#expression, __VA_ARGS__)

#define MGLTestAssertNil(myself, expression, ...) \
    _XCTPrimitiveAssertNil(myself, expression, @#expression, __VA_ARGS__)

#define MGLTestAssertNotNil(myself, expression, ...) \
    _XCTPrimitiveAssertNotNil(myself, expression, @#expression, __VA_ARGS__)


@interface MGLMapViewIntegrationTest : XCTestCase <MGLMapViewDelegate>
@property (nonatomic) MGLMapView *mapView;
@property (nonatomic) MGLStyle *style;
@property (nonatomic) XCTestExpectation *styleLoadingExpectation;
@property (nonatomic) XCTestExpectation *renderFinishedExpectation;
@property (nonatomic) void (^regionDidChange)(MGLMapView *mapView, BOOL animated);
@property (nonatomic) void (^regionIsChanging)(MGLMapView *mapView);



// Utility methods
- (void)waitForMapViewToFinishLoadingStyleWithTimeout:(NSTimeInterval)timeout;
- (void)waitForMapViewToBeRenderedWithTimeout:(NSTimeInterval)timeout;
@end
