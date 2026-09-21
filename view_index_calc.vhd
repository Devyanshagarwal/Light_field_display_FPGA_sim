-- =============================================================================
-- view_index_calc.vhd
--
-- Per-subpixel view selection for a slanted-lenticular autostereoscopic
-- display. For output pixel (x, y) and colour c in {0=R, 1=G, 2=B}:
--
--     view(x, y, c) = floor( N * frac( (3x + c - 3ky) / (3P) ) )
--
-- (Multiplying numerator and denominator by 3 removes the c/3 subpixel offset.)
--
-- k (lens slope) and P (lens pitch, in subpixels) are provided as Q16.16
-- fixed-point constants. Defaults: k = 1/3, P = 4.5 -> classic 3-view-slanted
-- lens; N_VIEWS = 8 -> eight-view interleave.
--
-- Fully combinational. Consumers should register the outputs.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity view_index_calc is
    generic (
        N_VIEWS  : integer := 8;
        K_FIXED  : integer := 21845;   -- k * 2^16, k ~= 0.3333
        P3_FIXED : integer := 884736   -- 3*P * 2^16, P = 4.5
    );
    port (
        x   : in  unsigned(11 downto 0);
        y   : in  unsigned(11 downto 0);
        v_r : out unsigned(3 downto 0);
        v_g : out unsigned(3 downto 0);
        v_b : out unsigned(3 downto 0)
    );
end entity;

architecture rtl of view_index_calc is
    constant SCALE  : integer := 65536;
    -- Additive offset guarantees the numerator is non-negative before mod.
    -- Must exceed 3 * K_FIXED * V_MAX; 512 * P3_FIXED handles y up to ~6900.
    constant OFFSET : integer := 512 * P3_FIXED;

    function calc_view(x_v, y_v, c : integer) return integer is
        variable num, adj, frac_pt : integer;
    begin
        num     := (3 * x_v + c) * SCALE - 3 * K_FIXED * y_v;
        adj     := num + OFFSET;
        frac_pt := adj mod P3_FIXED;
        return (N_VIEWS * frac_pt) / P3_FIXED;
    end function;
begin
    v_r <= to_unsigned(calc_view(to_integer(x), to_integer(y), 0), 4);
    v_g <= to_unsigned(calc_view(to_integer(x), to_integer(y), 1), 4);
    v_b <= to_unsigned(calc_view(to_integer(x), to_integer(y), 2), 4);
end architecture;
