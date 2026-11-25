# Empty app: only used to let Xcode create the provisioning profile for BUNDLE_ID.
cmake_minimum_required(VERSION 3.20)
project(Signing OBJC)
add_executable(SliceSpike MACOSX_BUNDLE main.m)
target_link_libraries(SliceSpike "-framework UIKit" "-framework Foundation")
set_target_properties(SliceSpike PROPERTIES MACOSX_BUNDLE_GUI_IDENTIFIER "${BUNDLE_ID}"
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${BUNDLE_ID}" XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
  XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${TEAM_ID}" XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY 2)
