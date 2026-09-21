-- =============================================================================
-- mvpr_top.vhd
--
-- Multi-view pixel router for an 8-view slanted-lenticular display.
--
-- Pipeline:
--   Stage 0 : pixel_counter emits (x, y); view_index_calc computes vR/vG/vB;
--             view_addr = y*H_ACTIVE + x issued to external view memories.
--   Stage 1 : view indices and DE registered; external memories return
--             view_rgb (all N views for this address, packed low-view-first).
--   Stage 2 : 3-way mux selects R from view[vR], G from view[vG], B from
--             view[vB]. Result registered to output.
--
-- Latency = 2 cycles from pixel_counter output to pixel_rgb output.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mvpr_top is
    generic (
        H_ACTIVE : integer := 64;
        V_ACTIVE : integer := 48;
        N_VIEWS  : integer := 8;
        K_FIXED  : integer := 21845;
        P3_FIXED : integer := 884736
    );
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        start_frame : in  std_logic;
        -- External view memory interface (1-cycle read latency)
        view_addr   : out unsigned(15 downto 0);
        view_rgb    : in  std_logic_vector(N_VIEWS*24-1 downto 0);
        -- Output pixel stream
        pixel_rgb   : out std_logic_vector(23 downto 0);
        pixel_de    : out std_logic;
        pixel_x     : out unsigned(11 downto 0);
        pixel_y     : out unsigned(11 downto 0);
        -- Routed view indices exposed for verification/debug
        dbg_v_r     : out unsigned(3 downto 0);
        dbg_v_g     : out unsigned(3 downto 0);
        dbg_v_b     : out unsigned(3 downto 0);
        frame_done  : out std_logic
    );
end entity;

architecture rtl of mvpr_top is
    -- Stage 0 (combinational from pixel_counter)
    signal x_s, y_s               : unsigned(11 downto 0);
    signal de_s                   : std_logic;
    signal fd_s                   : std_logic;
    signal v_r_s, v_g_s, v_b_s    : unsigned(3 downto 0);

    -- Stage 1 pipeline registers
    signal v_r_r1, v_g_r1, v_b_r1 : unsigned(3 downto 0);
    signal de_r1, fd_r1           : std_logic;
    signal x_r1, y_r1             : unsigned(11 downto 0);

    -- Stage 2 output registers
    signal pixel_rgb_n            : std_logic_vector(23 downto 0);
    signal pixel_rgb_r2           : std_logic_vector(23 downto 0);
    signal de_r2, fd_r2           : std_logic;
    signal x_r2, y_r2             : unsigned(11 downto 0);
    signal v_r_r2, v_g_r2, v_b_r2 : unsigned(3 downto 0);

    type rgb_arr_t is array (0 to N_VIEWS-1) of std_logic_vector(23 downto 0);
    signal view_arr : rgb_arr_t;
begin
    ----------------------------------------------------------------------------
    -- Stage 0: address & view-index generation
    ----------------------------------------------------------------------------
    U_CNT : entity work.pixel_counter
        generic map (H_ACTIVE => H_ACTIVE, V_ACTIVE => V_ACTIVE)
        port map (
            clk         => clk,
            rst_n       => rst_n,
            start_frame => start_frame,
            x           => x_s,
            y           => y_s,
            de          => de_s,
            frame_done  => fd_s
        );

    U_VIC : entity work.view_index_calc
        generic map (
            N_VIEWS  => N_VIEWS,
            K_FIXED  => K_FIXED,
            P3_FIXED => P3_FIXED
        )
        port map (x => x_s, y => y_s, v_r => v_r_s, v_g => v_g_s, v_b => v_b_s);

    view_addr <= to_unsigned(to_integer(y_s) * H_ACTIVE + to_integer(x_s), 16);

    ----------------------------------------------------------------------------
    -- Stage 1: register view indices, DE, coords; memories are reading
    ----------------------------------------------------------------------------
    process(clk, rst_n) begin
        if rst_n = '0' then
            v_r_r1 <= (others => '0');
            v_g_r1 <= (others => '0');
            v_b_r1 <= (others => '0');
            de_r1  <= '0';
            fd_r1  <= '0';
            x_r1   <= (others => '0');
            y_r1   <= (others => '0');
        elsif rising_edge(clk) then
            v_r_r1 <= v_r_s;
            v_g_r1 <= v_g_s;
            v_b_r1 <= v_b_s;
            de_r1  <= de_s;
            fd_r1  <= fd_s;
            x_r1   <= x_s;
            y_r1   <= y_s;
        end if;
    end process;

    -- Unpack the flat view bus into an array (view 0 in the low bits)
    unpack: for i in 0 to N_VIEWS-1 generate
        view_arr(i) <= view_rgb((i+1)*24-1 downto i*24);
    end generate;

    -- 3-way subpixel mux: independent view selection per colour channel
    pixel_rgb_n <= view_arr(to_integer(v_r_r1))(23 downto 16) &
                   view_arr(to_integer(v_g_r1))(15 downto  8) &
                   view_arr(to_integer(v_b_r1))( 7 downto  0);

    ----------------------------------------------------------------------------
    -- Stage 2: output register
    ----------------------------------------------------------------------------
    process(clk, rst_n) begin
        if rst_n = '0' then
            pixel_rgb_r2 <= (others => '0');
            de_r2  <= '0';
            fd_r2  <= '0';
            x_r2   <= (others => '0');
            y_r2   <= (others => '0');
            v_r_r2 <= (others => '0');
            v_g_r2 <= (others => '0');
            v_b_r2 <= (others => '0');
        elsif rising_edge(clk) then
            pixel_rgb_r2 <= pixel_rgb_n;
            de_r2  <= de_r1;
            fd_r2  <= fd_r1;
            x_r2   <= x_r1;
            y_r2   <= y_r1;
            v_r_r2 <= v_r_r1;
            v_g_r2 <= v_g_r1;
            v_b_r2 <= v_b_r1;
        end if;
    end process;

    pixel_rgb  <= pixel_rgb_r2;
    pixel_de   <= de_r2;
    pixel_x    <= x_r2;
    pixel_y    <= y_r2;
    dbg_v_r    <= v_r_r2;
    dbg_v_g    <= v_g_r2;
    dbg_v_b    <= v_b_r2;
    frame_done <= fd_r2;
end architecture;
