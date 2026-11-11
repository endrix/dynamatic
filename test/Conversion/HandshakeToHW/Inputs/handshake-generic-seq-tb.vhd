-- A testbench for the generic init and sequential multiplier of
-- data/vhdl/handshake/generic, used by handshake-generic-seq-ghdl.mlir.
-- The init: the token it holds at reset is INITIAL_VALUE, then it is a
-- one-slot buffer. The multiplier: the low W bits of the product, for random
-- operands under random back-pressure, at the step S.
-- Fails (severity failure) on a wrong result.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
  generic (
    W : positive := 8;
    S : positive := 3;
    V : string := "5"; -- the init's value, in decimal
    BITS : string := "00000101" -- the same in W bits
  );
end entity;

architecture sim of tb is
  subtype word is std_logic_vector(W - 1 downto 0);
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal i_in, i_out, a, b, p : word := (others => '0');
  signal i_iv, i_ir, i_ov, i_or : std_logic := '0';
  signal d_iv, d_ir, d_ov, d_or : std_logic := '0';
  signal av, ar, bv, br, pv, pr : std_logic := '0';

  function word_of(text : string) return word is
    variable r : word;
  begin
    assert text'length = W report "BITS is not W bits" severity failure;
    for i in 0 to W - 1 loop
      if text(text'low + i) = '1' then
        r(W - 1 - i) := '1';
      else
        r(W - 1 - i) := '0';
      end if;
    end loop;
    return r;
  end function;
begin
  u_init : entity work.handshake_init(arch) generic map(V, W)
    port map(clk, rst, i_in, i_iv, i_ir, i_out, i_ov, i_or);
  u_init0 : entity work.handshake_init_dataless(arch)
    port map(clk, rst, d_iv, d_ir, d_ov, d_or);
  u_mul : entity work.handshake_muli_sequential(arch) generic map(S, W)
    port map(clk, rst, a, av, ar, b, bv, br, p, pv, pr);

  process
    variable lfsr : unsigned(62 downto 0) := to_unsigned(1, 63);
    variable checks : natural := 0;
    variable xa, xb, want : word;
    variable waited : natural;

    procedure step is
    begin
      for i in 1 to 63 loop
        lfsr := lfsr(61 downto 0) & (lfsr(62) xor lfsr(61));
      end loop;
    end procedure;

    procedure tick is
    begin
      clk <= '1'; wait for 1 ns; clk <= '0'; wait for 1 ns;
    end procedure;

    procedure check(cond : boolean; what : string) is
    begin
      assert cond
        report "handshake generic seq, W=" & integer'image(W) & ": wrong " & what
        severity failure;
      checks := checks + 1;
    end procedure;

    -- A W-bit word of fresh bits (W may be above 63).
    impure function fresh return word is
      variable r : word;
    begin
      for i in 0 to W - 1 loop
        if i mod 60 = 0 then
          step;
        end if;
        r(i) := lfsr(i mod 60);
      end loop;
      return r;
    end function;
  begin
    tick; tick;
    rst <= '0';
    wait for 1 ns;
    -- The init: full at reset, with the value; it takes nothing until the
    -- token leaves.
    check(i_ov = '1' and i_out = word_of(BITS), "init, the token at reset");
    check(i_ir = '0', "init, ready while full");
    check(d_ov = '1' and d_ir = '0', "init without data, the token at reset");
    i_in <= not word_of(BITS); i_iv <= '1'; d_iv <= '1';
    tick; wait for 1 ns;
    check(i_ov = '1' and i_out = word_of(BITS), "init, the token held");
    check(d_ov = '1' and d_ir = '0', "init without data, the token held");
    i_or <= '1'; d_or <= '1';
    wait for 1 ns;
    check(i_out = word_of(BITS), "init, the token leaving");
    tick; wait for 1 ns;
    -- Empty: a wire, and the next token is the input's.
    check(i_ir = '1' and i_ov = '1' and i_out = not word_of(BITS), "init, empty, the input through");
    check(d_ir = '1' and d_ov = '1', "init without data, empty");
    i_or <= '0'; d_or <= '0';
    wait for 1 ns;
    tick; wait for 1 ns;
    -- Not taken: the input is held, and the unit is full again.
    i_in <= word_of(BITS); i_iv <= '0'; d_iv <= '0';
    wait for 1 ns;
    check(i_ir = '0' and i_ov = '1' and i_out = not word_of(BITS), "init, the input held");
    check(d_ir = '0' and d_ov = '1', "init without data, full again");

    -- The multiplier.
    for i in 1 to 60 loop
      xa := fresh; xb := fresh;
      if i = 1 then xa := (others => '1'); xb := (others => '1'); end if;
      if i = 2 then xb := (others => '0'); end if;
      want := std_logic_vector(resize(unsigned(xa) * unsigned(xb), W));
      a <= xa; b <= xb;
      step;
      av <= '1'; bv <= lfsr(3); pr <= '0';
      wait for 1 ns;
      -- One operand alone is not taken.
      if bv = '0' then
        check(ar = '0', "muli, an operand alone taken");
        tick;
        bv <= '1'; wait for 1 ns;
      end if;
      check(ar = '1' and br = '1', "muli, idle, the operands not taken");
      tick; wait for 1 ns;
      av <= '0'; bv <= '0';
      waited := 0;
      while pv = '0' loop
        check(waited <= (W + S - 1) / S + 1, "muli, latency");
        tick; wait for 1 ns;
        waited := waited + 1;
      end loop;
      check(waited = (W + S - 1) / S, "muli, cycles of a multiply");
      check(p = want, "muli, product");
      -- Held until taken, and nothing new accepted meanwhile.
      av <= '1'; bv <= '1';
      for h in 1 to to_integer(lfsr(5 downto 4)) loop
        tick; wait for 1 ns;
        check(pv = '1' and p = want, "muli, the product held");
        check(ar = '0', "muli, operands taken over a waiting product");
      end loop;
      pr <= '1'; wait for 1 ns;
      check(ar = '1', "muli, operands not taken as the product leaves");
      av <= '0'; bv <= '0'; wait for 1 ns;
      tick; wait for 1 ns;
      check(pv = '0', "muli, the product gone");
    end loop;
    report "handshake generic seq, W=" & integer'image(W) & ": " & integer'image(checks)
      & " checks as expected";
    wait;
  end process;
end architecture;
