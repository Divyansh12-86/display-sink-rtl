// =============================================================================
// File: main_sdl.cpp
// Description: Real-Time Interactive Multi-Resolution & Rate Display Emulator.
//              Features:
//              - Native video resolution auto-detection (SD, HD, FHD, 2K, 4K)
//              - Bidirectional hardware scaling (1:1 Native, Upscaling & Downscaling)
//              - Zero-distortion multi-resolution dynamic texture management
//              - High-speed real-time simulation engine (lag-free 60 FPS playback)
//              - Cadence-accurate refresh rate pacing (24Hz, 30Hz, 45Hz, 60Hz)
//              - 6 Togglable display sources with graceful empty-slot fallbacks
// =============================================================================

#include <iostream>
#include <vector>
#include <string>
#include <chrono>
#include <thread>
#include <filesystem>
#include <fstream>
#include <algorithm>
#include <SDL.h>

#include "Vdisplay_sink_top.h"
#include "verilated.h"

namespace fs = std::filesystem;

// Window presentation viewport (Responsive 16:9 desktop presentation)
constexpr int WIN_WIDTH  = 960;
constexpr int WIN_HEIGHT = 540;

// 6 Togglable Display Sources
enum DisplaySourceMode {
    MODE_COLORBARS = 0,
    MODE_GRAYSCALE = 1,
    MODE_GEOMETRY  = 2,
    MODE_MOTION    = 3,
    MODE_VIDEO1    = 4,
    MODE_VIDEO2    = 5
};

// Decoded Video Frame Memory
struct VideoFrame {
    int width = 0;
    int height = 0;
    std::vector<uint32_t> pixels; // 0x00RRGGBB
};

// Video Slot Handler with Native Resolution Recognition
class VideoPlayer {
public:
    std::string slot_name;
    std::string folder_path;
    std::vector<VideoFrame> frames;
    size_t current_frame = 0;
    bool loaded = false;

    int native_w = 0;
    int native_h = 0;
    std::string native_label = "None";
    int native_res_mode = 1; // 0=480p, 1=720p, 2=1080p

    VideoPlayer(const std::string& name, const std::string& path)
        : slot_name(name), folder_path(path) {
        scan_and_load();
    }

    void scan_and_load() {
        frames.clear();
        current_frame = 0;
        loaded = false;
        native_w = 0;
        native_h = 0;
        native_label = "None";

        if (!fs::exists(folder_path)) {
            return;
        }

        std::vector<std::string> file_list;
        for (const auto& entry : fs::directory_iterator(folder_path)) {
            if (entry.is_regular_file()) {
                std::string ext = entry.path().extension().string();
                std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
                if (ext == ".ppm" || ext == ".bmp" || ext == ".raw") {
                    file_list.push_back(entry.path().string());
                }
            }
        }

        std::sort(file_list.begin(), file_list.end());

        for (const auto& file_path : file_list) {
            VideoFrame frame;
            std::string ext = fs::path(file_path).extension().string();
            std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

            bool ok = false;
            if (ext == ".ppm") ok = load_ppm(file_path, frame);
            else if (ext == ".bmp") ok = load_bmp(file_path, frame);
            else if (ext == ".raw") ok = load_raw(file_path, frame);

            if (ok && frame.width > 0 && frame.height > 0) {
                frames.push_back(std::move(frame));
            }
        }

        if (!frames.empty()) {
            loaded = true;
            native_w = frames[0].width;
            native_h = frames[0].height;

            // Recognize native resolution standard
            if (native_w == 640 && native_h == 480) {
                native_label = "480p SD";
                native_res_mode = 0;
            } else if (native_w == 1280 && native_h == 720) {
                native_label = "720p HD";
                native_res_mode = 1;
            } else if (native_w == 1920 && native_h == 1080) {
                native_label = "1080p FHD";
                native_res_mode = 2;
            } else if (native_w == 2560 && native_h == 1440) {
                native_label = "1440p 2K QHD";
                native_res_mode = 2;
            } else if (native_w == 3840 && native_h == 2160) {
                native_label = "2160p 4K UHD";
                native_res_mode = 2;
            } else {
                native_label = std::to_string(native_w) + "x" + std::to_string(native_h) + " Custom";
                if (native_w <= 800) native_res_mode = 0;
                else if (native_w <= 1400) native_res_mode = 1;
                else native_res_mode = 2;
            }

            std::cout << "[INFO] " << slot_name << ": Loaded " << frames.size()
                      << " frames (Native: " << native_w << "x" << native_h
                      << " [" << native_label << "]) from " << folder_path << "\n";
        }
    }

    uint32_t get_pixel(int target_x, int target_y, int active_dst_w, int active_dst_h) const {
        if (!loaded || frames.empty()) return 0;

        const auto& cur = frames[current_frame];
        if (cur.pixels.empty() || cur.width <= 0 || cur.height <= 0) return 0;

        int sx, sy;
        if (cur.width == active_dst_w && cur.height == active_dst_h) {
            sx = target_x;
            sy = target_y;
        } else {
            // Proportional coordinate scaling across entire target display window
            sx = (target_x * cur.width) / (active_dst_w > 0 ? active_dst_w : 1);
            sy = (target_y * cur.height) / (active_dst_h > 0 ? active_dst_h : 1);
        }

        if (sx < 0) sx = 0;
        if (sx >= cur.width) sx = cur.width - 1;
        if (sy < 0) sy = 0;
        if (sy >= cur.height) sy = cur.height - 1;

        return cur.pixels[sy * cur.width + sx];
    }

    void advance() {
        if (loaded && !frames.empty()) {
            current_frame = (current_frame + 1) % frames.size();
        }
    }

private:
    static bool load_ppm(const std::string& path, VideoFrame& out) {
        std::ifstream f(path, std::ios::binary);
        if (!f.is_open()) return false;

        std::string magic;
        f >> magic;
        if (magic != "P6") return false;

        int w, h, max_val;
        f >> w >> h >> max_val;
        f.get(); // newline
        if (w <= 0 || h <= 0 || max_val <= 0 || max_val > 255) return false;

        std::vector<uint8_t> rgb_bytes(w * h * 3);
        f.read(reinterpret_cast<char*>(rgb_bytes.data()), rgb_bytes.size());
        if (f.gcount() != static_cast<std::streamsize>(rgb_bytes.size())) return false;

        out.width = w;
        out.height = h;
        out.pixels.resize(w * h);
        for (int i = 0; i < w * h; ++i) {
            uint32_t r = rgb_bytes[i * 3 + 0];
            uint32_t g = rgb_bytes[i * 3 + 1];
            uint32_t b = rgb_bytes[i * 3 + 2];
            out.pixels[i] = (r << 16) | (g << 8) | b;
        }
        return true;
    }

    static bool load_bmp(const std::string& path, VideoFrame& out) {
        std::ifstream f(path, std::ios::binary);
        if (!f.is_open()) return false;

        uint8_t header[54];
        f.read(reinterpret_cast<char*>(header), 54);
        if (f.gcount() < 54 || header[0] != 'B' || header[1] != 'M') return false;

        uint32_t data_offset = *reinterpret_cast<uint32_t*>(&header[10]);
        int32_t w = *reinterpret_cast<int32_t*>(&header[18]);
        int32_t h = *reinterpret_cast<int32_t*>(&header[22]);
        uint16_t bpp = *reinterpret_cast<uint16_t*>(&header[28]);
        if (bpp != 24 && bpp != 32) return false;

        bool flip = true;
        if (h < 0) { h = -h; flip = false; }
        if (w <= 0 || h <= 0) return false;

        f.seekg(data_offset, std::ios::beg);
        int bytes_per_px = bpp / 8;
        int row_padded = ((w * bytes_per_px + 3) / 4) * 4;
        std::vector<uint8_t> row_buf(row_padded);

        out.width = w;
        out.height = h;
        out.pixels.resize(w * h);

        for (int y = 0; y < h; ++y) {
            int target_y = flip ? (h - 1 - y) : y;
            f.read(reinterpret_cast<char*>(row_buf.data()), row_padded);
            for (int x = 0; x < w; ++x) {
                uint8_t b = row_buf[x * bytes_per_px + 0];
                uint8_t g = row_buf[x * bytes_per_px + 1];
                uint8_t r = row_buf[x * bytes_per_px + 2];
                out.pixels[target_y * w + x] = (r << 16) | (g << 8) | b;
            }
        }
        return true;
    }

    static bool load_raw(const std::string& path, VideoFrame& out) {
        std::ifstream f(path, std::ios::binary | std::ios::ate);
        if (!f.is_open()) return false;
        size_t file_size = f.tellg();
        f.seekg(0, std::ios::beg);

        int w = 0, h = 0;
        if (file_size == 640 * 480 * 3)       { w = 640;  h = 480; }
        else if (file_size == 1280 * 720 * 3)  { w = 1280; h = 720; }
        else if (file_size == 1920 * 1080 * 3) { w = 1920; h = 1080; }
        else return false;

        std::vector<uint8_t> rgb_bytes(file_size);
        f.read(reinterpret_cast<char*>(rgb_bytes.data()), file_size);

        out.width = w;
        out.height = h;
        out.pixels.resize(w * h);
        for (int i = 0; i < w * h; ++i) {
            uint32_t r = rgb_bytes[i * 3 + 0];
            uint32_t g = rgb_bytes[i * 3 + 1];
            uint32_t b = rgb_bytes[i * 3 + 2];
            out.pixels[i] = (r << 16) | (g << 8) | b;
        }
        return true;
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Initialize SDL2 Video Subsystem
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        std::cerr << "[ERROR] SDL_Init failed: " << SDL_GetError() << std::endl;
        return 1;
    }

    SDL_Window* window = SDL_CreateWindow(
        "Display Sink RTL - Interactive Multi-Resolution & Rate Emulator",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        WIN_WIDTH,
        WIN_HEIGHT,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
    );

    if (!window) {
        std::cerr << "[ERROR] SDL_CreateWindow failed: " << SDL_GetError() << std::endl;
        SDL_Quit();
        return 1;
    }

    SDL_Renderer* renderer = SDL_CreateRenderer(
        window,
        -1,
        SDL_RENDERER_ACCELERATED
    );

    if (!renderer) {
        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
    }

    if (!renderer) {
        std::cerr << "[ERROR] SDL_CreateRenderer failed: " << SDL_GetError() << std::endl;
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    // Locate repository media folder
    std::string base_media = "media";
    if (!fs::exists(base_media)) {
        if (fs::exists("../media")) base_media = "../media";
        else if (fs::exists("../../media")) base_media = "../../media";
    }

    VideoPlayer video1("Custom Video 1", base_media + "/video1");
    VideoPlayer video2("Custom Video 2", base_media + "/video2");

    // Instantiate Verilated RTL Top Model
    auto top = std::make_unique<Vdisplay_sink_top>();

    // Initial RTL Signals
    top->clk           = 0;
    top->rst_n         = 0;
    top->enable        = 0;
    top->res_mode      = 1; // 720p initial target
    top->src_res_mode  = 1; // 720p initial source
    top->rate_mode     = 3; // 60Hz default
    top->pat_mode      = 0; // SMPTE Color Bars default
    top->ext_video_rgb = 0;
    top->ext_video_sel = 0;
    top->fast_sim_en   = 1; // Enable real-time 60 FPS simulation
    top->csc_enable    = 0; // RGB bypass
    top->gamma_mode    = 0; // Linear bypass
    top->dither_enable = 0; // Dither off

    top->s_axis_tdata  = 0;
    top->s_axis_tvalid = 0;
    top->s_axis_tuser  = 0;
    top->s_axis_tlast  = 0;

    // Reset sequence: 20 clock ticks
    for (int i = 0; i < 20; ++i) {
        top->clk = !top->clk;
        top->eval();
    }
    top->rst_n  = 1;
    top->enable = 1;

    DisplaySourceMode current_mode = MODE_COLORBARS;

    // Active Texture & Dynamic Framebuffer dimensions
    int cur_panel_w = 1280;
    int cur_panel_h = 720;

    SDL_Texture* texture = SDL_CreateTexture(
        renderer,
        SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING,
        cur_panel_w,
        cur_panel_h
    );

    std::vector<uint32_t> framebuffer(cur_panel_w * cur_panel_h, 0xFF000000);

    auto update_panel_dimensions = [&](int w, int h) {
        if (cur_panel_w != w || cur_panel_h != h) {
            cur_panel_w = w;
            cur_panel_h = h;
            if (texture) SDL_DestroyTexture(texture);
            texture = SDL_CreateTexture(
                renderer,
                SDL_PIXELFORMAT_ARGB8888,
                SDL_TEXTUREACCESS_STREAMING,
                cur_panel_w,
                cur_panel_h
            );
            framebuffer.assign(cur_panel_w * cur_panel_h, 0xFF000000);
        }
    };

    std::cout << "=================================================================\n";
    std::cout << " Display Sink RTL - Interactive Multi-Resolution & Rate Emulator   \n";
    std::cout << "=================================================================\n";
    std::cout << " Display Source Toggles (6 Options):\n";
    std::cout << "   [F1] / [KP1] : Mode 1 - SMPTE 8-Bar Color Bars (Hardware Built-in)\n";
    std::cout << "   [F2] / [KP2] : Mode 2 - 0-255 Grayscale Ramp (Hardware Built-in)\n";
    std::cout << "   [F3] / [KP3] : Mode 3 - Calibration Geometry Grid (Hardware Built-in)\n";
    std::cout << "   [F4] / [KP4] : Mode 4 - Animated Motion Target (Hardware Built-in)\n";
    std::cout << "   [F5] / [KP5] : Mode 5 - Custom Video 1 (media/video1/)\n";
    std::cout << "   [F6] / [KP6] : Mode 6 - Custom Video 2 (media/video2/)\n";
    std::cout << "   [V]  / [P]   : Cycle through all 6 Display Modes sequentially\n";
    std::cout << " Hardware Display Resolution Controls (1:1 Native, Upscaling, Downscaling):\n";
    std::cout << "   [1] 480p Display  (640x480 active)\n";
    std::cout << "   [2] 720p Display  (1280x720 active)\n";
    std::cout << "   [3] 1080p Display (1920x1080 active)\n";
    std::cout << " Refresh Rate Cadence:\n";
    std::cout << "   [4] 24 Hz (Cinema) | [5] 30 Hz | [6] 45 Hz | [7] 60 Hz (Smooth Motion)\n";
    std::cout << " Pipeline Modifiers:\n";
    std::cout << "   [C] Toggle CSC (RGB <-> YCbCr) | [G] Cycle Gamma | [D] Toggle Dither\n";
    std::cout << "   [R] Rescan & Reload custom video folders\n";
    std::cout << "   [ESC] / [Q] Quit\n";
    std::cout << "=================================================================\n";

    auto print_scaling_status = [&]() {
        const char* res_names[] = { "480p SD", "720p HD", "1080p FHD" };
        std::string src_desc;
        if (current_mode == MODE_VIDEO1 && video1.loaded) {
            src_desc = "Custom Video 1 [" + video1.native_label + "]";
        } else if (current_mode == MODE_VIDEO2 && video2.loaded) {
            src_desc = "Custom Video 2 [" + video2.native_label + "]";
        } else {
            src_desc = "Built-in Test Pattern";
        }

        std::string mode_desc;
        if (top->src_res_mode == top->res_mode) {
            mode_desc = "1:1 Native Passthrough";
        } else if (top->src_res_mode < top->res_mode) {
            mode_desc = "Upscaled";
        } else {
            mode_desc = "Downscaled";
        }

        std::cout << "[SCALING] Source: " << src_desc
                  << " -> Target Display: " << res_names[top->res_mode]
                  << " (" << mode_desc << ")\n";
    };

    auto apply_mode = [&](DisplaySourceMode mode) {
        current_mode = mode;
        switch (mode) {
            case MODE_COLORBARS:
                top->pat_mode = 0;
                top->src_res_mode = top->res_mode;
                std::cout << "[CONTROL] Mode 1: SMPTE 8-Bar Color Bars Active\n";
                break;
            case MODE_GRAYSCALE:
                top->pat_mode = 1;
                top->src_res_mode = top->res_mode;
                std::cout << "[CONTROL] Mode 2: 0-255 Horizontal Grayscale Ramp Active\n";
                break;
            case MODE_GEOMETRY:
                top->pat_mode = 2;
                top->src_res_mode = top->res_mode;
                std::cout << "[CONTROL] Mode 3: Calibration Geometry Grid Active\n";
                break;
            case MODE_MOTION:
                top->pat_mode = 3;
                top->src_res_mode = top->res_mode;
                std::cout << "[CONTROL] Mode 4: Animated Motion Target Active\n";
                break;
            case MODE_VIDEO1:
                if (video1.loaded) {
                    top->pat_mode = 4;
                    top->src_res_mode = video1.native_res_mode;
                    // Match display resolution to native on initial selection
                    top->res_mode = video1.native_res_mode;
                    int target_w = (top->res_mode == 0) ? 640 : (top->res_mode == 1) ? 1280 : 1920;
                    int target_h = (top->res_mode == 0) ? 480 : (top->res_mode == 1) ? 720 : 1080;
                    update_panel_dimensions(target_w, target_h);
                    std::cout << "[CONTROL] Mode 5: Custom User Video 1 Active ("
                              << video1.frames.size() << " frames, Native: "
                              << video1.native_label << ")\n";
                    print_scaling_status();
                } else {
                    top->pat_mode = 0;
                    top->src_res_mode = top->res_mode;
                    std::cout << "[INFO] Mode 5: Custom Video 1 selected, but no frames found in media/video1/.\n";
                    std::cout << "       (Add videos via: python3 scripts/load_video.py <file> 1  OR  --demo 1)\n";
                    std::cout << "       Gracefully falling back to Default Pattern 1 (SMPTE Color Bars).\n";
                }
                break;
            case MODE_VIDEO2:
                if (video2.loaded) {
                    top->pat_mode = 5;
                    top->src_res_mode = video2.native_res_mode;
                    // Match display resolution to native on initial selection
                    top->res_mode = video2.native_res_mode;
                    int target_w = (top->res_mode == 0) ? 640 : (top->res_mode == 1) ? 1280 : 1920;
                    int target_h = (top->res_mode == 0) ? 480 : (top->res_mode == 1) ? 720 : 1080;
                    update_panel_dimensions(target_w, target_h);
                    std::cout << "[CONTROL] Mode 6: Custom User Video 2 Active ("
                              << video2.frames.size() << " frames, Native: "
                              << video2.native_label << ")\n";
                    print_scaling_status();
                } else {
                    top->pat_mode = 0;
                    top->src_res_mode = top->res_mode;
                    std::cout << "[INFO] Mode 6: Custom Video 2 selected, but no frames found in media/video2/.\n";
                    std::cout << "       (Add videos via: python3 scripts/load_video.py <file> 2  OR  --demo 2)\n";
                    std::cout << "       Gracefully falling back to Default Pattern 1 (SMPTE Color Bars).\n";
                }
                break;
        }
    };

    bool running = true;
    SDL_Event event;

    int cur_x = 0;
    int cur_y = 0;
    bool last_vsync = false;

    auto last_fps_time = std::chrono::steady_clock::now();
    int frame_counter = 0;

    while (running && !Verilated::gotFinish()) {
        auto frame_start_time = std::chrono::steady_clock::now();

        // Handle User Input Events
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                running = false;
            } else if (event.type == SDL_KEYDOWN) {
                switch (event.key.keysym.sym) {
                    case SDLK_ESCAPE:
                    case SDLK_q:
                        running = false;
                        break;

                    // 6 Display Mode Toggles
                    case SDLK_F1:
                    case SDLK_KP_1:
                        apply_mode(MODE_COLORBARS);
                        break;
                    case SDLK_F2:
                    case SDLK_KP_2:
                        apply_mode(MODE_GRAYSCALE);
                        break;
                    case SDLK_F3:
                    case SDLK_KP_3:
                        apply_mode(MODE_GEOMETRY);
                        break;
                    case SDLK_F4:
                    case SDLK_KP_4:
                        apply_mode(MODE_MOTION);
                        break;
                    case SDLK_F5:
                    case SDLK_KP_5:
                        apply_mode(MODE_VIDEO1);
                        break;
                    case SDLK_F6:
                    case SDLK_KP_6:
                        apply_mode(MODE_VIDEO2);
                        break;

                    // Sequential Mode Cycle Key
                    case SDLK_v:
                    case SDLK_p: {
                        int next_mode = (static_cast<int>(current_mode) + 1) % 6;
                        apply_mode(static_cast<DisplaySourceMode>(next_mode));
                        break;
                    }

                    // Reload Video folders from disk
                    case SDLK_r:
                        std::cout << "[CONTROL] Rescanning custom video directories...\n";
                        video1.scan_and_load();
                        video2.scan_and_load();
                        apply_mode(current_mode);
                        break;

                    // Target Display Resolution Switching
                    case SDLK_1: {
                        top->res_mode = 0; // 480p
                        update_panel_dimensions(640, 480);
                        if (current_mode < MODE_VIDEO1) top->src_res_mode = 0;
                        print_scaling_status();
                        break;
                    }
                    case SDLK_2: {
                        top->res_mode = 1; // 720p
                        update_panel_dimensions(1280, 720);
                        if (current_mode < MODE_VIDEO1) top->src_res_mode = 1;
                        print_scaling_status();
                        break;
                    }
                    case SDLK_3: {
                        top->res_mode = 2; // 1080p
                        update_panel_dimensions(1920, 1080);
                        if (current_mode < MODE_VIDEO1) top->src_res_mode = 2;
                        print_scaling_status();
                        break;
                    }

                    // Refresh Rate Switching
                    case SDLK_4:
                        top->rate_mode = 0; // 24 Hz
                        std::cout << "[CONTROL] Refresh Rate -> 24 Hz (Cinema Motion Cadence)\n";
                        break;
                    case SDLK_5:
                        top->rate_mode = 1; // 30 Hz
                        std::cout << "[CONTROL] Refresh Rate -> 30 Hz\n";
                        break;
                    case SDLK_6:
                        top->rate_mode = 2; // 45 Hz
                        std::cout << "[CONTROL] Refresh Rate -> 45 Hz\n";
                        break;
                    case SDLK_7:
                        top->rate_mode = 3; // 60 Hz
                        std::cout << "[CONTROL] Refresh Rate -> 60 Hz (Smooth Motion)\n";
                        break;

                    // Color Space Conversion Toggle
                    case SDLK_c:
                        top->csc_enable = !top->csc_enable;
                        std::cout << "[CONTROL] CSC Mode -> " << (top->csc_enable ? "BT.709 YCbCr Active" : "RGB Bypass") << "\n";
                        break;

                    // Gamma LUT Cycling
                    case SDLK_g:
                        top->gamma_mode = (top->gamma_mode + 1) % 3;
                        if (top->gamma_mode == 0) std::cout << "[CONTROL] Gamma Mode -> Linear Passthrough\n";
                        else if (top->gamma_mode == 1) std::cout << "[CONTROL] Gamma Mode -> Gamma 2.2 Curve\n";
                        else std::cout << "[CONTROL] Gamma Mode -> sRGB Curve\n";
                        break;

                    // Dithering Toggle
                    case SDLK_d:
                        top->dither_enable = !top->dither_enable;
                        std::cout << "[CONTROL] Dithering / FRC -> " << (top->dither_enable ? "Enabled (Bayer 2x2)" : "Disabled") << "\n";
                        break;

                    // Simulation Fidelity Mode Toggle (Real-Time Smooth 60 FPS vs Strict Physical Clock Cycle Emulation)
                    case SDLK_s:
                        top->fast_sim_en = !top->fast_sim_en;
                        std::cout << "[SIMULATION FIDELITY] Mode -> "
                                  << (top->fast_sim_en ? "High-Speed Real-Time Simulation (Smooth 24/30/45/60 FPS)"
                                                       : "Strict Physical 150MHz Cycle-Accurate Clock Emulation")
                                  << "\n";
                        break;

                    default:
                        break;
                }
            }
        }

        // Active source and destination dimensions
        int active_src_w = (top->src_res_mode == 0) ? 640 : (top->src_res_mode == 1) ? 1280 : 1920;
        int active_src_h = (top->src_res_mode == 0) ? 480 : (top->src_res_mode == 1) ? 720 : 1080;

        int active_dst_w = (top->res_mode == 0) ? 640 : (top->res_mode == 1) ? 1280 : 1920;
        int active_dst_h = (top->res_mode == 0) ? 480 : (top->res_mode == 1) ? 720 : 1080;

        update_panel_dimensions(active_dst_w, active_dst_h);

        // Simulate RTL Clocks until a full video frame is completed
        bool frame_done = false;
        while (!frame_done) {
            // Provide external video pixel if current mode is Video 1 or 2 (mapped to active destination display raster)
            if (current_mode == MODE_VIDEO1 && video1.loaded) {
                top->ext_video_rgb = video1.get_pixel(top->cur_pixel_x, top->cur_pixel_y, active_dst_w, active_dst_h);
            } else if (current_mode == MODE_VIDEO2 && video2.loaded) {
                top->ext_video_rgb = video2.get_pixel(top->cur_pixel_x, top->cur_pixel_y, active_dst_w, active_dst_h);
            }

            // Rising Edge
            top->clk = 1;
            top->eval();

            // Active Panel Pixel Capture into Framebuffer
            // In strict hardware mode (fast_sim_en == 0), advance cur_x ONLY when cur_pixel_en is asserted,
            // preventing refresh rate changes from altering line length or frame geometry!
            bool pixel_valid = top->panel_de && (top->fast_sim_en || top->cur_pixel_en);
            if (pixel_valid) {
                if (cur_x < cur_panel_w && cur_y < cur_panel_h) {
                    uint32_t argb = 0xFF000000 |
                                    (static_cast<uint32_t>(top->panel_r) << 16) |
                                    (static_cast<uint32_t>(top->panel_g) << 8)  |
                                    (static_cast<uint32_t>(top->panel_b));
                    framebuffer[cur_y * cur_panel_w + cur_x] = argb;
                }
                cur_x++;
            } else if (!top->panel_de) {
                if (cur_x > 0) {
                    cur_x = 0;
                    cur_y++;
                }
            }

            // Vsync Rising Edge indicates end of frame
            if (top->panel_vsync && !last_vsync) {
                cur_x = 0;
                cur_y = 0;
                frame_done = true;

                // Advance video frames on frame completion
                if (current_mode == MODE_VIDEO1 && video1.loaded) {
                    video1.advance();
                } else if (current_mode == MODE_VIDEO2 && video2.loaded) {
                    video2.advance();
                }
            }
            last_vsync = top->panel_vsync;

            // Falling Edge
            top->clk = 0;
            top->eval();
        }

        // Push Framebuffer to SDL2 Texture and Render Window
        SDL_UpdateTexture(texture, nullptr, framebuffer.data(), cur_panel_w * sizeof(uint32_t));
        SDL_RenderClear(renderer);
        SDL_RenderCopy(renderer, texture, nullptr, nullptr);
        SDL_RenderPresent(renderer);

        // Refresh Rate Cadence Pacing (Eliminates lag and matches target cadence)
        int target_fps = (top->rate_mode == 0) ? 24 : (top->rate_mode == 1) ? 30 : (top->rate_mode == 2) ? 45 : 60;
        double target_frame_ms = 1000.0 / target_fps;
        auto frame_sim_time = std::chrono::steady_clock::now();
        std::chrono::duration<double, std::milli> sim_elapsed = frame_sim_time - frame_start_time;

        if (sim_elapsed.count() < target_frame_ms) {
            SDL_Delay(static_cast<Uint32>(target_frame_ms - sim_elapsed.count()));
        }

        frame_counter++;
        auto now = std::chrono::steady_clock::now();
        std::chrono::duration<double> elapsed = now - last_fps_time;
        if (elapsed.count() >= 0.5) {
            double fps = frame_counter / elapsed.count();

            std::string source_info;
            if (current_mode == MODE_VIDEO1 && video1.loaded) {
                source_info = "Video 1 [" + video1.native_label + "]";
            } else if (current_mode == MODE_VIDEO2 && video2.loaded) {
                source_info = "Video 2 [" + video2.native_label + "]";
            } else {
                const char* pat_names[] = { "SMPTE Bars", "Grayscale", "Geometry", "Motion", "Video 1 (Empty)", "Video 2 (Empty)" };
                source_info = pat_names[current_mode];
            }

            const char* res_labels[] = { "480p", "720p", "1080p" };
            std::string scale_label;
            if (current_mode >= MODE_VIDEO1 && ((current_mode == MODE_VIDEO1 && video1.loaded) || (current_mode == MODE_VIDEO2 && video2.loaded))) {
                if (top->src_res_mode == top->res_mode) scale_label = "1:1 Native";
                else if (top->src_res_mode < top->res_mode) scale_label = "Upscaled";
                else scale_label = "Downscaled";
            } else {
                scale_label = "Direct";
            }

            const char* rate_labels[] = { "24Hz", "30Hz", "45Hz", "60Hz" };
            std::string sim_mode_str = top->fast_sim_en ? "Real-Time" : "Strict HW";
            std::string title = "Display Sink RTL [" + std::to_string(static_cast<int>(fps + 0.5)) + " FPS, " + sim_mode_str + "] | "
                              + source_info + " -> "
                              + res_labels[top->res_mode] + " (" + scale_label + ") @ "
                              + rate_labels[top->rate_mode] + " | [1..3: Res, 4..7: Rate, S: Mode, F1..F6/V: Source]";
            SDL_SetWindowTitle(window, title.c_str());
            frame_counter = 0;
            last_fps_time = now;
        }
    }

    // Cleanup Resources
    if (texture) SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    std::cout << "[INFO] Interactive Display Viewer closed gracefully.\n";
    return 0;
}
