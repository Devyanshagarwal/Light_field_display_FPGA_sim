# mvpr — Multi-View Pixel Router (VHDL)

A streaming, per-subpixel pixel router for an 8-view slanted-lenticular
autostereoscopic display, of the kind used in glasses-free 3D and light-field
displays. Real-time RGB pipeline with independent view selection per colour
channel.

## What it does

An autostereoscopic panel physically routes each subpixel through a slanted
lens sheet to a specific viewing angle. To render a 3D scene the FPGA must,
for every output pixel `(x, y)` and each subpixel channel `c` in {R, G, B},
pick the correct view (out of N pre-rendered viewpoints) and fetch the
matching sample. This block implements that routing using van Berkel's
canonical formula:

```
view(x, y, c) = floor( N * frac( (3x + c - 3ky) / (3P) ) )
```

with `k` (lens slope) and `P` (lens pitch in subpixels) as Q16.16 fixed-point
generics.

## Pipeline

```
                                              +----------+
   pixel_counter --(x, y, DE)------+----------+          |
                                   |          |view_idx  |--(vR, vG, vB)
                                   |          |  _calc   |
                                   |          +----------+
                                   |
                     view_addr = y*W + x  ---> [ 8 view memories ]
                                                      |
                                                view_rgb (8 x 24-bit)
                                                      |
                                             +--------v---------+
                                             | 3-way subpixel   |
                              (vR, vG, vB) ->|      mux         |-> pixel_rgb
                                             +------------------+
```

- **Stage 0:** pixel counter + view-index math + memory address.
- **Stage 1:** register view indices; external view memories return data.
- **Stage 2:** 3 independent muxes select R from view[vR], G from view[vG],
  B from view[vB]. Result registered to output.

Latency: 2 cycles. One output pixel per clock at full rate.

## Files

- `pixel_counter.vhd` — frame-timing counter with start/done handshake.
- `view_index_calc.vhd` — van Berkel formula, three parallel subpixel evals.
- `mvpr_top.vhd` — top-level pipeline integrating both.
- `tb_mvpr.vhd` — testbench with 8 synthetic view memories, ASCII
  visualization of the routing pattern, and pass/fail check.

## Running on EDA Playground

1. Go to <https://www.edaplayground.com/>.
2. **Language:** VHDL. **Simulator:** GHDL 4.0.0 (or newer). Tick
   **Open EPWave after run** if you want waveforms.
3. Add the four `.vhd` files to the workspace. Set `tb_mvpr` as the top
   entity.
4. **Run**.

Alternatively, locally with GHDL:

```bash
ghdl -a --std=08 pixel_counter.vhd view_index_calc.vhd mvpr_top.vhd tb_mvpr.vhd
ghdl -e --std=08 tb_mvpr
ghdl -r --std=08 tb_mvpr
```

## Expected output

Each output row prints as 64 digits (0–7) representing the R-channel view
index chosen for each pixel. The pattern of digits shows the slanted lens
interleave — you'll see diagonal bands stepping across the frame at the
slope determined by `k` and `P`. Last lines show:

```
Total pixels captured : 3072
Expected pixel count  : 3072
RESULT: PASS (pixel count matches)
```

## Design decisions worth noting on your portfolio

- **Per-subpixel routing** (not per-pixel). Each of R, G, B can source from
  a *different* view — this is what real lenticular displays require and
  what distinguishes a proper router from a naive column interleaver.
- **8 parallel view memories, single mux stage.** Trades BRAM count for
  guaranteed single-cycle throughput regardless of which views R/G/B pick.
- **Combinational modulo/divide** in `view_index_calc` for demo clarity.
  For synthesis to high pixel rates this would be pipelined and the divide
  replaced with multiply-by-reciprocal (P and k are compile-time constants).
- **Q16.16 fixed-point** for lens parameters — matches how real display
  controllers store calibration data.

## Natural extensions (good next commits)

1. **Linear interpolation between neighbouring views** — replace the
   `floor()` with a fractional view index and blend two adjacent views'
   subpixels. This is what real light-field displays do to reduce
   view-boundary artefacts.
2. **AXI-Stream wrapper** — add `tvalid`/`tready`/`tlast`/`tuser` on the
   output for drop-in use in Xilinx/AMD IP integrator flows.
3. **Real view content** — extend the testbench to read 8 PPM files
   (rendered views of a rotating object) and dump the interleaved output
   as a PPM, so you can display the actual routed frame.
4. **Runtime-configurable P and k** via an AXI-Lite register interface —
   turns this from fixed-geometry IP into a lens-calibration-friendly
   block.
5. **Pipelined divider** in `view_index_calc` — replace the `/` and `mod`
   operators with a synthesizable reciprocal-multiply and report Fmax
   before/after in the README.
