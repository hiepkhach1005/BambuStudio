#pragma once
#include <functional>
#include <memory>
#include <string>
#include <vector>

// Whole-document facade over libslic3r. Not thread safe: every method runs on the engine thread, except
// cancel() and slice_status(). Slicing runs on its own thread on Print's private copy of the model.
class Engine
{
public:
    Engine(const std::string &resources, const std::string &data_dir, const std::string &temp_dir);
    ~Engine();
    // JSON in, JSON out. Errors come back as {"error": "..."}.
    std::string call(const std::string &cmd, const std::string &args);
    // Interleaved float32 xyz + normal, 3 vertices per triangle, in volume space. Key from state().objects[].volumes[].mesh
    std::vector<float> mesh(long long key);
    // Painted facets (xyz+normal+state as 7 floats). kind: 0 support, 1 seam, 2 color
    std::vector<float> painted(int object, int volume, int kind);
    // Preview segments, 12 floats each: x0 y0 z0 x1 y1 z1 width height role extruder layer speed
    std::vector<float> preview(int plate);
    std::string        slice_status();
    void               cancel();

private:
    struct Impl;
    std::unique_ptr<Impl> p;
};
