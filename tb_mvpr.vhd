-- =============================================================================
-- tb_mvpr.vhd
--
-- Testbench for mvpr_top. Fills 8 view memories with distinct solid-grey
-- intensities (view N -> intensity N/7). Under routing this makes the
-- slanted-lens interleave pattern immediately visible: each output pixel's
-- brightness reflects which view the router selected for it.
--
-- Outputs to console:
--   - Per-row string of digits 0..7 = R-channel view index (routing pattern)
--   - Pixel count and R-channel checksum on frame end
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_mvpr is
end entity;

architecture sim of tb_mvpr is
    constant H_ACTIVE : integer := 64;
    constant V_ACTIVE : integer := 48;
    constant N_VIEWS  : integer := 8;

    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal start_frame : std_logic := '0';
    signal view_addr   : unsigned(15 downto 0);
    signal view_rgb_r  : std_logic_vector(N_VIEWS*24-1 downto 0) := (others => '0');
    signal pixel_rgb   : std_logic_vector(23 downto 0);
    signal pixel_de    : std_logic;
    signal pixel_x     : unsigned(11 downto 0);
    signal pixel_y     : unsigned(11 downto 0);
    signal dbg_v_r     : unsigned(3 downto 0);
    signal dbg_v_g     : unsigned(3 downto 0);
    signal dbg_v_b     : unsigned(3 downto 0);
    signal frame_done  : std_logic;

    type view_mem_t  is array (0 to H_ACTIVE*V_ACTIVE-1) of std_logic_vector(23 downto 0);
    type view_bank_t is array (0 to N_VIEWS-1) of view_mem_t;

    constant DIGITS : string(1 to 8) := "01234567";
begin
    -- 100 MHz clock
    clk <= not clk after 5 ns;

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    DUT: entity work.mvpr_top
        generic map (
            H_ACTIVE => H_ACTIVE,
            V_ACTIVE => V_ACTIVE,
            N_VIEWS  => N_VIEWS
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            start_frame => start_frame,
            view_addr   => view_addr,
            view_rgb    => view_rgb_r,
            pixel_rgb   => pixel_rgb,
            pixel_de    => pixel_de,
            pixel_x     => pixel_x,
            pixel_y     => pixel_y,
            dbg_v_r     => dbg_v_r,
            dbg_v_g     => dbg_v_g,
            dbg_v_b     => dbg_v_b,
            frame_done  => frame_done
        );

    ----------------------------------------------------------------------------
    -- View memory model: 8 banks of H*V pixels each, filled with a uniform
    -- grey whose intensity encodes the view index. 1-cycle read latency.
    ----------------------------------------------------------------------------
    mem_proc: process(clk)
        variable init_done : boolean := false;
        variable views     : view_bank_t;
        variable intensity : integer;
        variable ipix      : std_logic_vector(7 downto 0);
    begin
        if not init_done then
            for v in 0 to N_VIEWS-1 loop
                intensity := (v * 255) / (N_VIEWS - 1);
                ipix      := std_logic_vector(to_unsigned(intensity, 8));
                for i in 0 to H_ACTIVE*V_ACTIVE-1 loop
                    views(v)(i) := ipix & ipix & ipix;
                end loop;
            end loop;
            init_done := true;
        end if;

        if rising_edge(clk) then
            for v in 0 to N_VIEWS-1 loop
                view_rgb_r((v+1)*24-1 downto v*24) <= views(v)(to_integer(view_addr));
            end loop;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Stimulus: reset, one frame, then finish.
    ----------------------------------------------------------------------------
    stim: process
    begin
        rst_n <= '0';
        wait for 25 ns;
        rst_n <= '1';
        wait for 20 ns;

        report "----- Multi-view pixel router: streaming one frame -----";
        report "Frame: " & integer'image(H_ACTIVE) & "x" & integer'image(V_ACTIVE) &
               "   Views: " & integer'image(N_VIEWS);
        report "Below: R-channel view index per output pixel (0..7)";

        wait until rising_edge(clk);
        start_frame <= '1';
        wait until rising_edge(clk);
        start_frame <= '0';

        wait until frame_done = '1';
        wait for 50 ns;

        report "----- Done -----";
        finish;
    end process;

    ----------------------------------------------------------------------------
    -- Pixel capture: build an ASCII line per output row showing the R-channel
    -- view index chosen. Also accumulate a simple checksum on the R byte.
    ----------------------------------------------------------------------------
    capture: process(clk)
        variable line_buf : line;
        variable row_str  : string(1 to H_ACTIVE);
        variable col      : integer := 0;
        variable row      : integer := 0;
        variable pcnt     : integer := 0;
        variable csum     : integer := 0;
        variable dig      : integer;
    begin
        if rising_edge(clk) then
            if pixel_de = '1' then
                dig             := to_integer(dbg_v_r);
                row_str(col+1)  := DIGITS(dig + 1);
                csum            := csum + to_integer(unsigned(pixel_rgb(23 downto 16)));
                pcnt            := pcnt + 1;
                if col = H_ACTIVE - 1 then
                    write(line_buf, row_str);
                    writeline(output, line_buf);
                    col := 0;
                    row := row + 1;
                else
                    col := col + 1;
                end if;
            end if;
            if frame_done = '1' then
                report "Total pixels captured : " & integer'image(pcnt);
                report "R-channel byte sum    : " & integer'image(csum);
                report "Expected pixel count  : " &
                       integer'image(H_ACTIVE * V_ACTIVE);
                if pcnt = H_ACTIVE * V_ACTIVE then
                    report "RESULT: PASS (pixel count matches)";
                else
                    report "RESULT: FAIL (pixel count mismatch)" severity error;
                end if;
            end if;
        end if;
    end process;
end architecture;
