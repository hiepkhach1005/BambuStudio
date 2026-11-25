#include "slice_core.hpp"
#include <chrono>
#include <boost/filesystem.hpp>
#include "libslic3r/Utils.hpp"
#include "libslic3r/PresetBundle.hpp"
#include "libslic3r/Model.hpp"
#include "libslic3r/Print.hpp"
#include "libslic3r/Format/bbs_3mf.hpp"
#include "libslic3r/GCode/GCodeProcessor.hpp"

using namespace Slic3r;

namespace {
struct Case { const char *name; const char *model; bool support; const char *support_type; };
const Case kCases[] = {
    {"cube", "20mm_cube.obj", false, "normal(auto)"},
    {"idler_normal_support", "extruder_idler.obj", true, "normal(auto)"},
    {"frog_tree_support", "frog_legs.obj", true, "tree(auto)"},
    {"stand", "ipadstand.obj", false, "normal(auto)"},
};
}

int run_slice_cases(const std::string &resources, const std::string &models, const std::string &out_dir,
                    const std::function<void(const std::string &)> &log)
{
    namespace fs = boost::filesystem;
    using clock  = std::chrono::steady_clock;
    int failed   = 0;
    set_resources_dir(resources);
    set_var_dir(resources + "/images");
    set_data_dir(out_dir);
    set_temporary_dir(out_dir);

    PresetBundle bundle;
    try {
        const auto t0  = clock::now();
        const auto res = bundle.load_vendor_configs_from_json(resources + "/profiles", "BBL", PresetBundle::LoadSystem, ForwardCompatibilitySubstitutionRule::EnableSilent);
        log("presets loaded: " + std::to_string(res.second) + " in " +
            std::to_string(std::chrono::duration_cast<std::chrono::milliseconds>(clock::now() - t0).count()) + " ms");
        if (!bundle.printers.select_preset_by_name("Bambu Lab P1S 0.4 nozzle", true)) throw std::runtime_error("printer preset not selected");
        if (!bundle.prints.select_preset_by_name("0.20mm Standard @BBL X1C", true)) throw std::runtime_error("process preset not selected");
        bundle.filaments.select_preset_by_name("Bambu PLA Basic @BBL X1C", true);
        bundle.filament_presets = {"Bambu PLA Basic @BBL X1C"};
    } catch (const std::exception &e) {
        log(std::string("FAIL presets: ") + e.what());
        return 1;
    }

    for (const Case &c : kCases) {
        try {
            const auto t0 = clock::now();
            DynamicPrintConfig config = bundle.full_config();
            config.set_deserialize_strict("enable_support", c.support ? "1" : "0");
            config.set_deserialize_strict("support_type", c.support_type);

            Model model = Model::read_from_file(models + "/" + c.model, nullptr, nullptr, LoadStrategy::AddDefaultInstances);
            for (ModelObject *o : model.objects) {
                o->center_around_origin();
                o->ensure_on_bed();
                o->instances.front()->set_offset(X, 128.);
                o->instances.front()->set_offset(Y, 128.);
            }
            Print print;
            print.set_status_silent();
            print.apply(model, config);
            const auto err = print.validate();
            if (!err.string.empty()) throw std::runtime_error("validate: " + err.string);
            print.process();
            GCodeProcessorResult result;
            const std::string    path = print.export_gcode(out_dir + "/" + c.name + ".gcode", &result, nullptr);
            log(std::string("OK ") + c.name + " layers=" + std::to_string(print.objects().front()->layer_count()) + " bytes=" + std::to_string(fs::file_size(path)) + " ms=" +
                std::to_string(std::chrono::duration_cast<std::chrono::milliseconds>(clock::now() - t0).count()));
        } catch (const std::exception &e) {
            ++failed;
            log(std::string("FAIL ") + c.name + ": " + e.what());
        }
    }
    // Project files next to the output: open with their own settings, slice plate 1.
    std::vector<fs::path> projects;
    for (auto &e : fs::directory_iterator(out_dir))
        if (e.path().extension() == ".3mf") projects.push_back(e.path());
    std::sort(projects.begin(), projects.end());
    for (const fs::path &p : projects) {
        try {
            const auto t0 = clock::now();
            DynamicPrintConfig        loaded; // empty like the desktop app: options are created from their definitions
            ConfigSubstitutionContext subst(ForwardCompatibilitySubstitutionRule::Enable);
            PlateDataPtrs             plates;
            std::vector<Preset *>     project_presets;
            bool   is_bbl = false;
            Semver version;
            Model  model = Model::read_from_file(p.string(), &loaded, &subst, LoadStrategy::LoadModel | LoadStrategy::LoadConfig | LoadStrategy::AddDefaultInstances,
                                                 &plates, &project_presets, &is_bbl, &version);
            DynamicPrintConfig config = bundle.full_config();
            config.apply(loaded);
            size_t facets = 0;
            for (ModelObject *o : model.objects) facets += o->facets_count();
            log("OPEN " + p.filename().string() + " objects=" + std::to_string(model.objects.size()) + " plates=" + std::to_string(plates.size()) +
                " facets=" + std::to_string(facets) + " printer=" + config.opt_string("printer_settings_id") + " ms=" +
                std::to_string(std::chrono::duration_cast<std::chrono::milliseconds>(clock::now() - t0).count()));
            if (!plates.empty() && !plates.front()->objects_and_instances.empty()) {
                for (ModelObject *o : model.objects)
                    for (ModelInstance *i : o->instances) i->printable = false;
                for (const auto &oi : plates.front()->objects_and_instances)
                    if (oi.first < (int) model.objects.size() && oi.second < (int) model.objects[oi.first]->instances.size())
                        model.objects[oi.first]->instances[oi.second]->printable = true;
            }
            for (ModelObject *o : model.objects)
                for (ModelInstance *i : o->instances) i->print_volume_state = i->printable ? ModelInstancePVS_Inside : ModelInstancePVS_Fully_Outside;
            Print print;
            print.set_status_silent();
            print.apply(model, config);
            const auto err = print.validate();
            if (!err.string.empty()) throw std::runtime_error("validate: " + err.string);
            print.process();
            GCodeProcessorResult result;
            const std::string    path = print.export_gcode(out_dir + "/" + p.stem().string() + ".gcode", &result, nullptr);
            log("OK 3mf layers=" + std::to_string(print.objects().front()->layer_count()) + " bytes=" + std::to_string(fs::file_size(path)) + " ms=" +
                std::to_string(std::chrono::duration_cast<std::chrono::milliseconds>(clock::now() - t0).count()));
            release_PlateData_list(plates);
            for (Preset *preset : project_presets) delete preset;
        } catch (const std::exception &e) {
            ++failed;
            log("FAIL " + p.filename().string() + ": " + e.what());
        }
    }
    log(failed ? "DONE with failures" : "DONE all passed");
    return failed;
}
