#import "SearchVC.h"
#import "CompassView.h"
#import "LocationManager.h"
#import "SearchBannerChecker.h"

#include "../../geometry/angles.hpp"
#include "../../geometry/distance_on_sphere.hpp"
#include "../../platform/settings.hpp"
#include "../../indexer/mercator.hpp"
#include "../../map/framework.hpp"
#include "../../search/result.hpp"

SearchVC * g_searchVC = nil;
volatile int g_queryId = 0;

@interface Wrapper : NSObject
{
  search::Result * m_result;
}
- (id)initWithResult:(search::Result const &) res;
- (search::Result const *)get;
@end

@implementation Wrapper
- (id)initWithResult:(search::Result const &) res
{
  if ((self = [super init]))
    m_result = new search::Result(res);
  return self;
}

- (void)dealloc
{
  delete m_result;
  [super dealloc];
}

- (search::Result const *)get
{
  return m_result;
}
@end

static void OnSearchResultCallback(search::Result const & res, int queryId)
{
  if (g_searchVC && queryId == g_queryId)
  {
    // end marker means that the search is finished
    if (!res.IsEndMarker())
    {
      Wrapper * w = [[Wrapper alloc] initWithResult:res];
      [g_searchVC performSelectorOnMainThread:@selector(addResult:)
                                 withObject:w
                              waitUntilDone:NO];
      [w release];
    }
  }
}

/////////////////////////////////////////////////////////////////////

@interface CustomView : UIView
@end
@implementation CustomView
- (void)layoutSubviews
{
  UISearchBar * searchBar = (UISearchBar *)[self.subviews objectAtIndex:0];
  [searchBar sizeToFit];
  UITableView * table = (UITableView *)[self.subviews objectAtIndex:1];
  CGRect rTable;
  rTable.origin = CGPointMake(searchBar.frame.origin.x, searchBar.frame.origin.y + searchBar.frame.size.height);
  rTable.size = self.bounds.size;
  rTable.size.height -= searchBar.bounds.size.height;
  table.frame = rTable;
}
@end

////////////////////////////////////////////////////////////////////
/// Key to store settings
#define SEARCH_MODE_SETTING     "SearchMode"
#define SEARCH_MODE_POPULARITY  "ByPopularity"
#define SEARCH_MODE_ONTHESCREEN "OnTheScreen"
#define SEARCH_MODE_NEARME      "NearMe"
#define SEARCH_MODE_DEFAULT     SEARCH_MODE_POPULARITY

@implementation SearchVC

// Controls visibility of information window with GPS location problems
//- (void)showOrHideGPSWarningIfNeeded
//{
//  if (m_searchBar.selectedScopeButtonIndex == 2)
//  {
//    if (m_warningViewText)
//    {
//      if (!m_warningView)
//      {
//        CGRect const rSearch = m_searchBar.frame;
//        CGFloat const h = rSearch.size.height / 3.0;
//        CGRect rWarning = CGRectMake(rSearch.origin.x, rSearch.origin.y + rSearch.size.height,
//                                   rSearch.size.width, 0);
//        m_warningView = [[UILabel alloc] initWithFrame:rWarning];
//        m_warningView.textAlignment = UITextAlignmentCenter;
//        m_warningView.numberOfLines = 0;
//        m_warningView.backgroundColor = [UIColor yellowColor];
//      
//        rWarning.size.height = h;
//
//        CGRect rTable = m_table.frame;
//        rTable.origin.y += h; 
//
//        [UIView animateWithDuration:0.5 animations:^{
//          [self.view addSubview:m_warningView];
//          m_table.frame = rTable;
//          m_warningView.frame = rWarning;
//        }];
//      }
//      m_warningView.text = m_warningViewText;
//      return;
//    }
//  }
//  // in all other cases hide this window
//  if (m_warningView)
//  {
//    CGRect const rSearch = m_searchBar.frame;
//    CGRect rTable = m_table.frame;
//    rTable.origin.y = rSearch.origin.y + rSearch.size.height;
//    [self.view sendSubviewToBack:m_warningView];
//  
//    [UIView animateWithDuration:0.5 
//                     animations:^{
//                       m_table.frame = rTable;
//                     }
//                     completion:^(BOOL finished){
//                       [m_warningView removeFromSuperview];
//                       [m_warningView release];
//                       m_warningView = nil;
//                     }];
//  }
//}

- (void)setSearchMode:(string const &)mode
{
  if (mode == SEARCH_MODE_POPULARITY)
  {
    m_searchBar.selectedScopeButtonIndex = 0;
    // @TODO switch search mode
    //m_framework->SearchEngine()->SetXXXXXX();
  }
  else if (mode == SEARCH_MODE_ONTHESCREEN)
  {
    m_searchBar.selectedScopeButtonIndex = 1;
    // @TODO switch search mode
    //m_framework->SearchEngine()->SetXXXXXX();
  }
  else // Search mode "Near me"
  {
    m_searchBar.selectedScopeButtonIndex = 2;
    // @TODO switch search mode
    //m_framework->SearchEngine()->SetXXXXXX();
  }
  Settings::Set(SEARCH_MODE_SETTING, mode);
//  [self showOrHideGPSWarningIfNeeded];
}

- (id)initWithFramework:(Framework *)framework andLocationManager:(LocationManager *)lm
{
  if ((self = [super initWithNibName:nil bundle:nil]))
  {
    m_framework = framework;
    m_locationManager = lm;
  }
  return self;
}

- (void)loadView
{
  // create user interface
  CustomView * parentView = [[[CustomView alloc] init] autorelease];
  parentView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;

  m_searchBar = [[UISearchBar alloc] init];
  m_searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  m_searchBar.delegate = self;
  m_searchBar.placeholder = NSLocalizedString(@"Search map", @"Search box placeholder text");
  m_searchBar.showsCancelButton = YES;
  m_searchBar.showsScopeBar = YES;
  m_searchBar.scopeButtonTitles = [NSArray arrayWithObjects:NSLocalizedString(@"By popularity", @"Search scope criteria"),
                                   NSLocalizedString(@"On the screen", @"Search scope criteria"),
                                   NSLocalizedString(@"Near me", @"Search scope criteria"), nil];
  [parentView addSubview:m_searchBar];

  m_table = [[UITableView alloc] init];
  m_table.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
  m_table.delegate = self;
  m_table.dataSource = self;
  [parentView addSubview:m_table];

  self.view = parentView;
}

- (void)clearResults
{
  m_results.clear();
}

- (void)dealloc
{
//  [m_warningViewText release];
  g_searchVC = nil;
  [m_searchBar release];
  [m_table release];
  [self clearResults];
  [super dealloc];
}

- (void)viewDidLoad
{
  g_searchVC = self;
}

- (void)viewDidUnload
{
  g_searchVC = nil;
  // to correctly free memory
  [m_searchBar release]; m_searchBar = nil;
  [m_table release]; m_table = nil;
  m_results.clear();
  
  [super viewDidUnload];
}

// Banner dialog handler
- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
  if (buttonIndex != alertView.cancelButtonIndex)
  {
    // Launch appstore
    string bannerUrl;
    Settings::Get(SETTINGS_REDBUTTON_URL_KEY, bannerUrl);
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithUTF8String:bannerUrl.c_str()]]];
  }
  // Close Search view
  [self dismissModalViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
  // Disable search for free version
  NSString * appID = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
  if ([appID compare:@"com.mapswithme.travelguide"] == NSOrderedSame)
  {
    // Hide scope bar
    m_searchBar.showsScopeBar = NO;
    // Display banner for paid version
    UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Search is only available in the full version of MapsWithMe. Would you like to get it now?", @"Search button pressed dialog title in the free version")
                                                     message:nil
                                                    delegate:self
                                           cancelButtonTitle:NSLocalizedString(@"Cancel", @"Search button pressed dialog Negative button in the free version")
                                           otherButtonTitles:NSLocalizedString(@"Get it now", @"Search button pressed dialog Positive button in the free version"), nil];
    [alert show];
    [alert release];
  }
  else
  {
    // load previously saved search mode
    string searchMode;
    if (!Settings::Get(SEARCH_MODE_SETTING, searchMode))
      searchMode = SEARCH_MODE_DEFAULT;
    [self setSearchMode:searchMode];

    [m_locationManager start:self];

    // show keyboard
    [m_searchBar becomeFirstResponder];
  }
  
  [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
  [m_locationManager stop:self];
  
  // hide keyboard immediately
  [m_searchBar resignFirstResponder];
  
  [super viewWillDisappear:animated];
}

- (void) didRotateFromInterfaceOrientation: (UIInterfaceOrientation) fromInterfaceOrientation
{
  [m_locationManager setOrientation:self.interfaceOrientation];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
  return YES;  // All orientations are supported.
}

//**************************************************************************
//*********** SearchBar handlers *******************************************
- (void)searchBar:(UISearchBar *)sender textDidChange:(NSString *)searchText
{
  [self clearResults];
  [m_table reloadData];
  ++g_queryId;

  if ([searchText length] > 0)
    m_framework->Search([[searchText precomposedStringWithCompatibilityMapping] UTF8String],
              bind(&OnSearchResultCallback, _1, g_queryId));
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
  [self dismissModalViewControllerAnimated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope
{
  string searchMode;
  switch (selectedScope)
  {
    case 0: searchMode = SEARCH_MODE_POPULARITY; break;
    case 1: searchMode = SEARCH_MODE_ONTHESCREEN; break;
    default: searchMode = SEARCH_MODE_NEARME; break;
  }
  [self setSearchMode:searchMode];
}
//*********** End of SearchBar handlers *************************************
//***************************************************************************

- (void)updateCellAngle:(UITableViewCell *)cell withIndex:(NSUInteger)index andAngle:(double)northDeg
{
  CLLocation * loc = [m_locationManager lastLocation];
  if (loc)
  {
    m2::PointD const center = m_results[index].GetFeatureCenter();
    double const angle = ang::AngleTo(m2::PointD(MercatorBounds::LonToX(loc.coordinate.longitude),
        MercatorBounds::LatToY(loc.coordinate.latitude)), center) + northDeg / 180. * math::pi;
    
    if (m_results[index].GetResultType() == search::Result::RESULT_FEATURE)
    {
      CompassView * cv = (CompassView *)cell.accessoryView;
      if (!cv)
      {
        float const h = m_table.rowHeight * 0.6;
        cv = [[CompassView alloc] initWithFrame:CGRectMake(0, 0, h, h)];
        cell.accessoryView = cv;
        [cv release];
      }
      cv.angle = angle;
    }
  }
}

- (void)updateCellDistance:(UITableViewCell *)cell withIndex:(NSUInteger)index
{
  CLLocation * loc = [m_locationManager lastLocation];
  if (loc)
  {
    m2::PointD const center = m_results[index].GetFeatureCenter();
    double const centerLat = MercatorBounds::YToLat(center.y);
    double const centerLon = MercatorBounds::XToLon(center.x);
    double const distance = ms::DistanceOnEarth(loc.coordinate.latitude, loc.coordinate.longitude, centerLat, centerLon);

    // @TODO use imperial system from the settings if needed
    // @TODO use meters too
    // NSLocalizedString(@"%.1lf m", @"Search results - Metres")
    // NSLocalizedString(@"%.1lf ft", @"Search results - Feet")
    // NSLocalizedString(@"%.1lf mi", @"Search results - Miles")
    // NSLocalizedString(@"%.1lf yd", @"Search results - Yards")
    cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%.1lf km", @"Search results - Kilometres"),
                                 distance / 1000.0];
  }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  return m_results.size();
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"SearchVCTableViewCell"];
  if (!cell)
  {
    cell = [[[UITableViewCell alloc]
           initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SearchVCTableViewCell"]
           autorelease];
  }
  
  cell.accessoryView = nil;
  if (indexPath.row < m_results.size())
  {
    search::Result const & r = m_results[indexPath.row];
    cell.textLabel.text = [NSString stringWithUTF8String:r.GetString()];
    if (r.GetResultType() == search::Result::RESULT_FEATURE)
      [self updateCellDistance:cell withIndex:indexPath.row];
    else
      cell.detailTextLabel.text = nil;
  }
  else
    cell.textLabel.text = @"BUG";
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  if (indexPath.row < m_results.size())
  {
    search::Result const & res = m_results[indexPath.row];
    switch(res.GetResultType())
    {
      // Zoom to the feature
    case search::Result::RESULT_FEATURE:
      m_framework->ShowRect(res.GetFeatureRect());
      [self searchBarCancelButtonClicked:m_searchBar];
      break;

    case search::Result::RESULT_SUGGESTION:
      [m_searchBar setText: [NSString stringWithFormat:@"%s ", res.GetSuggestionString()]];
      break;
    }
  }
}

- (void)addResult:(id)result
{
  m_results.push_back(*[result get]);
  [m_table reloadData];
}


//****************************************************************** 
//*********** Location manager callbacks ***************************
- (void)onLocationStatusChanged:(location::TLocationStatus)newStatus
{
//  [m_warningViewText release];
//  switch (newStatus)
//  {
//  case location::EDisabledByUser:
//    m_warningViewText = [[NSString alloc] initWithString:NSLocalizedString(@"Please enable Location Services", @"Search View - Location is disabled by user warning text")];
//    break;
//  case location::ENotSupported:
//    m_warningViewText = [[NSString alloc] initWithString:NSLocalizedString(@"Location Services are not supported", @"Search View - Location is not supported on the device warning text")];
//    break;
//  case location::EStarted:
//    m_warningViewText = [[NSString alloc] initWithString:NSLocalizedString(@"Determining your location...", @"Search View - Trying to determine location warning text")];
//    break;
//  case location::EStopped:
//  case location::EFirstEvent:
//    m_warningViewText = nil;
//    break;
//  }
//  [self showOrHideGPSWarningIfNeeded];
}

- (void)onGpsUpdate:(location::GpsInfo const &)info
{
  NSArray * cells = [m_table visibleCells];
  for (NSUInteger i = 0; i < cells.count; ++i)
  {
    UITableViewCell * cell = (UITableViewCell *)[cells objectAtIndex:i];
    [self updateCellDistance:cell withIndex:[m_table indexPathForCell:cell].row];
  }
}

- (void)onCompassUpdate:(location::CompassInfo const &)info
{
  NSArray * cells = [m_table visibleCells];
  for (NSUInteger i = 0; i < cells.count; ++i)
  {
    UITableViewCell * cell = (UITableViewCell *)[cells objectAtIndex:i];
    NSInteger const index = [m_table indexPathForCell:cell].row;
    if (m_results[index].GetResultType() == search::Result::RESULT_FEATURE)
      [self updateCellAngle:cell withIndex:index andAngle:((info.m_trueHeading < 0) ? info.m_magneticHeading : info.m_trueHeading)];
  }
}
//*********** End of Location manager callbacks ********************
//****************************************************************** 

//****************************************************************** 
//*********** Hack to keep Cancel button always enabled ************
- (void)enableCancelButton:(UISearchBar *)aSearchBar
{
  for (id subview in [aSearchBar subviews])
  {
    if ([subview isKindOfClass:[UIButton class]])
    {
      [subview setEnabled:TRUE];
      break;
    }
  }
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)aSearchBar
{
  [aSearchBar resignFirstResponder];
  [self performSelector:@selector(enableCancelButton:) withObject:aSearchBar afterDelay:0.0];
}
// ********** End of hack ******************************************
// *****************************************************************

@end
