-- A testbench for load-kill-drop-ghdl.mlir: the load that drops on a kill
-- (generated as dut, 2-bit addresses, 8-bit words), on the memory
-- controller's own read path (read_memory_arbiter of mc_support.vhd, one
-- port) and a synchronous memory holding 16 * a + 1 at address a. One step a
-- cycle: the requester's address, its ready for a word and the kill set, then
-- checked: whether its address is taken, whether a word is offered to it and
-- which. The rounds: three words owed at once -- one in the load's word slot,
-- one held by the controller, one address not yet granted -- and the
-- requester stopped; the three are dropped, nothing offered meanwhile, and
-- the requester's next address, offered from the kill on, gets its own word;
-- then a word passed on in the kill cycle is not dropped again, and an
-- address accepted in the kill cycle is. Fails (severity failure) on the
-- first thing wrong.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

entity tb is
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal addrIn, addrOut : std_logic_vector(1 downto 0) := (others => '0');
  signal addrIn_valid, addrIn_ready, addrOut_valid, addrOut_ready : std_logic := '0';
  signal dataFromMem, dataOut : std_logic_vector(7 downto 0) := (others => '0');
  signal dataFromMem_valid, dataFromMem_ready, dataOut_valid, dataOut_ready : std_logic := '0';
  signal kill : std_logic := '0';
  -- the controller's read path, one port
  signal pValid, ready, nReady, valid : std_logic_vector(0 downto 0);
  signal address_in : data_array(0 downto 0)(1 downto 0);
  signal data_out : data_array(0 downto 0)(7 downto 0);
  signal read_enable : std_logic;
  signal read_address : std_logic_vector(1 downto 0);
  signal data_from_memory : std_logic_vector(7 downto 0) := (others => '0');
begin
  clk <= not clk after 5 ns;

  dut : entity work.dut
    port map (clk => clk, rst => rst, addrIn => addrIn, addrIn_valid => addrIn_valid,
              addrIn_ready => addrIn_ready, addrOut => addrOut,
              addrOut_valid => addrOut_valid, addrOut_ready => addrOut_ready,
              dataFromMem => dataFromMem, dataFromMem_valid => dataFromMem_valid,
              dataFromMem_ready => dataFromMem_ready, dataOut => dataOut,
              dataOut_valid => dataOut_valid, dataOut_ready => dataOut_ready,
              kill => kill);

  pValid(0)     <= addrOut_valid;
  address_in(0) <= addrOut;
  addrOut_ready <= ready(0);
  nReady(0)     <= dataFromMem_ready;
  dataFromMem_valid <= valid(0);
  dataFromMem   <= data_out(0);

  arbiter : entity work.read_memory_arbiter
    generic map (ARBITER_SIZE => 1, ADDR_TYPE => 2, DATA_TYPE => 8)
    port map (rst => rst, clk => clk, pValid => pValid, ready => ready,
              address_in => address_in, nReady => nReady, valid => valid,
              data_out => data_out, read_enable => read_enable,
              read_address => read_address, data_from_memory => data_from_memory);

  -- a synchronous read: the word of the address enabled in a cycle, the next
  memory : process (clk) is
  begin
    if rising_edge(clk) then
      if read_enable = '1' then
        data_from_memory <= std_logic_vector(to_unsigned(16 * to_integer(unsigned(read_address)) + 1, 8));
      end if;
    end if;
  end process;

  process
    variable cycle : integer := 0;
    procedure step(a_v : std_logic; a : integer; d_r : std_logic; k : std_logic;
                   e_ar : std_logic; e_dv : std_logic; e_d : integer) is
    begin
      addrIn_valid <= a_v; addrIn <= std_logic_vector(to_unsigned(a, 2));
      dataOut_ready <= d_r; kill <= k;
      wait for 1 ns;
      assert addrIn_ready = e_ar
        report "cycle " & integer'image(cycle) & ": addrIn_ready " & std_logic'image(addrIn_ready)
        severity failure;
      assert dataOut_valid = e_dv
        report "cycle " & integer'image(cycle) & ": dataOut_valid " & std_logic'image(dataOut_valid)
        severity failure;
      if e_dv = '1' then
        assert to_integer(unsigned(dataOut)) = e_d
          report "cycle " & integer'image(cycle) & ": dataOut " &
                 integer'image(to_integer(unsigned(dataOut))) & ", expected " & integer'image(e_d)
          severity failure;
      end if;
      wait until rising_edge(clk);
      wait for 1 ns;
      cycle := cycle + 1;
    end procedure;
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait for 1 ns;
    -- address 1, granted at once; its word comes the next cycle, into the
    -- word slot, the requester not ready; address 2 granted meanwhile
    step('1', 1, '0', '0', '1', '0', 0);
    step('1', 2, '0', '0', '1', '1', 17);
    -- the word slot is full, the controller holds word 2, address 3 is taken
    -- into the address slot ungranted: three owed
    step('1', 3, '0', '0', '1', '1', 17);
    -- the requester is stopped
    step('0', 0, '0', '1', '0', '1', 17);
    -- the three words go, one a cycle, offered to nobody; the requester's
    -- next address waits behind the ungranted one (the address slot's ready
    -- is a register) and gets its own word
    step('1', 0, '1', '0', '0', '0', 0);
    step('1', 0, '1', '0', '0', '0', 0);
    step('1', 0, '1', '0', '1', '0', 0);
    step('0', 0, '1', '0', '1', '1', 1);
    step('0', 0, '1', '0', '1', '0', 0);
    -- a word passed on in the kill cycle is the stopped requester's own and
    -- is not dropped again: nothing owed after it
    step('1', 2, '1', '0', '1', '0', 0);
    step('0', 0, '1', '1', '1', '1', 33);
    step('1', 3, '1', '0', '1', '0', 0);
    step('0', 0, '1', '0', '1', '1', 49);
    step('0', 0, '1', '0', '1', '0', 0);
    -- an address accepted in the kill cycle is the stopped requester's: its
    -- word is dropped, and the next address's word delivered
    step('1', 1, '1', '1', '1', '0', 0);
    step('1', 2, '1', '0', '1', '0', 0);
    step('0', 0, '1', '0', '1', '1', 33);
    step('0', 0, '1', '0', '1', '0', 0);
    report "load kill drop: " & integer'image(cycle) & " cycles as expected";
    std.env.finish;
  end process;
end architecture;
