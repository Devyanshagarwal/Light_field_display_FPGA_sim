-- =============================================================================
-- pixel_counter.vhd
--
-- Emits (x, y) coordinates and a data-enable strobe for one full frame,
-- kicked off by a single-cycle start_frame pulse. frame_done asserts for one
-- cycle after the last pixel of the frame.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pixel_counter is
    generic (
        H_ACTIVE : integer := 64;
        V_ACTIVE : integer := 48
    );
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        start_frame : in  std_logic;
        x           : out unsigned(11 downto 0);
        y           : out unsigned(11 downto 0);
        de          : out std_logic;
        frame_done  : out std_logic
    );
end entity;

architecture rtl of pixel_counter is
    signal x_r          : unsigned(11 downto 0) := (others => '0');
    signal y_r          : unsigned(11 downto 0) := (others => '0');
    signal running      : std_logic := '0';
    signal frame_done_r : std_logic := '0';
begin
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            x_r          <= (others => '0');
            y_r          <= (others => '0');
            running      <= '0';
            frame_done_r <= '0';
        elsif rising_edge(clk) then
            frame_done_r <= '0';
            if running = '0' then
                if start_frame = '1' then
                    running <= '1';
                    x_r     <= (others => '0');
                    y_r     <= (others => '0');
                end if;
            else
                if x_r = to_unsigned(H_ACTIVE - 1, 12) then
                    x_r <= (others => '0');
                    if y_r = to_unsigned(V_ACTIVE - 1, 12) then
                        y_r          <= (others => '0');
                        running      <= '0';
                        frame_done_r <= '1';
                    else
                        y_r <= y_r + 1;
                    end if;
                else
                    x_r <= x_r + 1;
                end if;
            end if;
        end if;
    end process;

    x          <= x_r;
    y          <= y_r;
    de         <= running;
    frame_done <= frame_done_r;
end architecture;
