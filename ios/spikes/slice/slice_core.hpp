#pragma once
#include <functional>
#include <string>
// Gate I1c harness: slices the bundled test models with stock presets. Same code on iPad and Mac.
// Returns the number of failed cases; G-code files go to out_dir.
int run_slice_cases(const std::string &resources, const std::string &models, const std::string &out_dir,
                    const std::function<void(const std::string &)> &log);
