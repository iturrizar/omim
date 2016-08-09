#include "car_model.hpp"

#include "base/macros.hpp"

#include "indexer/classificator.hpp"

#include "std/vector.hpp"

namespace
{

routing::VehicleModel::InitListT const s_carLimits =
{
  { {"highway", "motorway"},       90 },
  { {"highway", "trunk"},          85 },
  { {"highway", "motorway_link"},  75 },
  { {"highway", "trunk_link"},     70 },
  { {"highway", "primary"},        65 },
  { {"highway", "primary_link"},   60 },
  { {"highway", "secondary"},      55 },
  { {"highway", "secondary_link"}, 50 },
  { {"highway", "tertiary"},       40 },
  { {"highway", "tertiary_link"},  30 },
  { {"highway", "residential"},    25 },
  { {"highway", "pedestrian"},     25 },
  { {"highway", "unclassified"},   25 },
  { {"highway", "service"},        15 },
  { {"highway", "living_street"},  10 },
  { {"highway", "road"},           10 },
  { {"highway", "track"},          5  },
  /// @todo: Add to classificator
  //{ {"highway", "shuttle_train"},  10 },
  //{ {"highway", "ferry"},          5  },
  //{ {"highway", "default"},        10 },
  /// @todo: Check type
  //{ {"highway", "construction"},   40 },
};

}  // namespace

namespace routing
{

CarModel::CarModel()
  : VehicleModel(classif(), s_carLimits)
{
  vector<AdditionalRoadTags> additionalTags =
  {
    {{ "route", "ferry", "motorcar" }, 15.0 },
    {{ "route", "ferry", "motor_vehicle" }, 15.0 },
    {{ "railway", "rail", "motor_vehicle" }, 40.0 },
    {{ "route", "shuttle_train"}, 40.0 },
  };

  SetAdditionalRoadTypes(classif(), additionalTags);
}

// static
CarModel const & CarModel::Instance()
{
  static CarModel const instance;
  return instance;
}

}  // namespace routing
