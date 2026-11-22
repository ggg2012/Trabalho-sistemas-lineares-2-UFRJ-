--Guilherme Guglielmo Gargaglione
--Data 15/11/2026
-- game_completo.vhd
-- All design units merged in one file (compile order matters):
--   ps2_keyboard -> top_keyboard -> menu -> game -> gameover -> main (TOP)
-- Target: Spartan-3A/3AN, Xilinx ISE (XST). Set 'main' as the top module.


-- ======================================================================
-- ps2_keyboard
-- ======================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--Description of pins used for the keyboard:
--clk: clock of 50MHz
--ps2_clk: clock provided by the own keyboard, to control the serial ps2_data
--ps2_data: data provided by the keyboard keys, in serial bits
--scan_code: data that identifies the character that is being pressed or released
--scan_code_ready: character binary identification can finally be read if equals to 1

entity ps2_keyboard is
    Port (
        clk             : in  STD_LOGIC;                      -- System clock (50 MHz)
        rst             : in  STD_LOGIC;                      -- Active high reset
        ps2_clk         : in  STD_LOGIC;                      -- Keyboard clock
        ps2_data        : in  STD_LOGIC;                      -- Keyboard data
        scan_code       : out STD_LOGIC_VECTOR (7 downto 0);  -- Extracted key code
        scan_code_ready : out STD_LOGIC                       -- High for 1 tick when data is valid
    );
end ps2_keyboard;

architecture Behavioral of ps2_keyboard is

    -- Shift register used to synchronize the asynchronous PS/2 clock to the system clock.
    -- Initializes to "111" because the PS/2 clock idles in a high state.
    signal ps2_clk_sync : STD_LOGIC_VECTOR(2 downto 0) := "111";

    -- Flag that goes high for one system clock cycle when a falling edge is detected on the PS/2 clock.
    signal falling_edge : STD_LOGIC;

    -- 11-bit shift register to hold the incoming PS/2 frame (1 start, 8 data, 1 parity, 1 stop).
    signal shift_reg    : STD_LOGIC_VECTOR(10 downto 0) := (others => '0');

    -- Counter to keep track of how many bits have been received in the current frame.
    signal bit_count    : integer range 0 to 11 := 0;

begin

    -- Synchronize PS/2 clock to avoid metastability
    process(clk, rst)
    begin
        if rst = '1' then
            ps2_clk_sync <= "111";
        elsif rising_edge(clk) then
            ps2_clk_sync <= ps2_clk_sync(1 downto 0) & ps2_clk;
        end if;
    end process;

    -- Edge Detection: A falling edge occurs when the previous state was '1' and the current state is '0'.
    -- We look at bits (2 downto 1) to ensure the signal is fully synchronized and stable.
    falling_edge <= '1' when (ps2_clk_sync(2 downto 1) = "10") else '0';

    -- Shift register to capture the 11-bit frame
    process(clk, rst)
    begin
        if rst = '1' then
            bit_count <= 0;
            shift_reg <= (others => '0');
            scan_code <= (others => '0');
            scan_code_ready <= '0';
        elsif rising_edge(clk) then
            -- Default assignment: ensures the ready signal is only high for a single clock tick
            scan_code_ready <= '0';

            -- PS/2 devices send data to the host on the falling edge of the PS/2 clock
            if falling_edge = '1' then

                -- Shift data right: PS/2 sends the LSB of the data first, preceded by a start bit.
                -- The incoming bit (ps2_data) enters at the MSB position.
                shift_reg <= ps2_data & shift_reg(10 downto 1);
                
                -- Check if a full 11-bit frame has been received
                if bit_count = 10 then
                    -- shift_reg(1) currently contains the start bit (which must be '0')
                    -- ps2_data currently holds the stop bit (which must be '1')
                    if shift_reg(1) = '0' and ps2_data = '1' then
                        -- Extract the 8 data bits (bits 2 through 9 of the shift register)
                        scan_code <= shift_reg(9 downto 2);
                        -- Signal to the rest of the system that valid data is available
                        scan_code_ready <= '1';
                    end if;
                    -- Reset the bit counter for the next incoming frame
                    bit_count <= 0;
                else
                    -- Increment the bit counter until the full frame is received
                    bit_count <= bit_count + 1;
                end if;
            end if;
        end if;
    end process;

end Behavioral;

-- ======================================================================
-- top_keyboard
-- ======================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

--Description of pins used for the keyboard:
--clk: clock of 50MHz
--ps2_clk: clock provided by the own keyboard, to control the serial ps2_data
--ps2_data: data provided by the keyboard keys, in serial bits
--keyboard_output: Controled by keys "W" and "S", that defines if the character is top or bottom
--button: controled by "enter" key

entity top_keyboard is
    Port (
        clk         : in  STD_LOGIC;
        rst         : in  STD_LOGIC;
        ps2_clk     : in  STD_LOGIC;
        ps2_data    : in  STD_LOGIC;
		keyboard_output : out STD_LOGIC;
		button : out STD_LOGIC
    );
end top_keyboard;

architecture Behavioral of top_keyboard is

    -- Component declaration of the serial bits reading
    component ps2_keyboard
        Port (
            clk             : in  STD_LOGIC;
            rst             : in  STD_LOGIC;
            ps2_clk         : in  STD_LOGIC;
            ps2_data        : in  STD_LOGIC;
            scan_code       : out STD_LOGIC_VECTOR (7 downto 0);
            scan_code_ready : out STD_LOGIC
        );
    end component;

    -- Internal signals, from the component ps2_keyboard
    signal scan_code       : STD_LOGIC_VECTOR(7 downto 0);
    signal scan_code_ready : STD_LOGIC;

    --defines if a key is being pressed
    signal is_break_code   : STD_LOGIC := '0';

    -- 1 if button enter is pressed
	signal enter : std_logic := '0';

    -- internal copy of keyboard_output (all registers are reset together)
    signal kb_out : std_logic := '0';

    -- Internal registers to hold the LED states

begin

	button <= enter;
	keyboard_output <= kb_out;

    -- Component maping
    Inst_ps2_keyboard: ps2_keyboard
        port map(
            clk             => clk,
            rst             => rst,
            ps2_clk         => ps2_clk,
            ps2_data        => ps2_data,
            scan_code       => scan_code,
            scan_code_ready => scan_code_ready
        );

    -- Process to control pressed keys
    process(clk, rst)
    begin
        -- reset reading
        if rst = '1' then
            is_break_code   <= '0';
            enter           <= '0';
            kb_out          <= '0';
            
        elsif rising_edge(clk) then

            --character binary identification can finally be read
            if scan_code_ready = '1' then

                --moment the key is released
                if scan_code = x"F0" then
                    is_break_code <= '1';
                else

                    --user released a key
                    if is_break_code = '1' then
                        case scan_code is
                            when x"5A"  => enter <= '0'; -- 'Enter' released
                            when others => null;
                        end case;
                        is_break_code <= '0'; 
                        
                    --user is pressing a key
                    else
                        -- Key pressed: turn ON the LED
                        case scan_code is
                            when x"1B"  => kb_out <= '1'; -- 'S' pressed
                            when x"1D"  => kb_out <= '0'; -- 'W' pressed
							when x"5A"  => enter <= '1'; -- 'Enter' pressed
                            when others => null;
                        end case;
                    end if;
                end if;
              end if;
            end if;
    end process;

end Behavioral;

-- ======================================================================
-- menu
-- ======================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

--explanation of the pins:
--LCD_DB to OE: Same as described at main.vhd
--rst: used to reset the display in case the player isn't at the title screen

entity menu is
    Port ( LCD_DB: out std_logic_vector(7 downto 0);
           RS:out std_logic;
           RW:out std_logic;
	   CLK:in std_logic;
	   OE:out std_logic;
	   rst:in std_logic);
end menu;

architecture Behavioral of menu is

	--type mstate is a type used for the display functions manipulation

	type mstate is (					  
		stFunctionSet,		 			
		stDisplayCtrlSet,
		stDisplayClear,
		stPowerOn_Delay,  				
		stFunctionSet_Delay,
		stDisplayCtrlSet_Delay, 	
		stDisplayClear_Delay,
		stInitDne,					
		stActWr,
		stPositionBelow,
		stPositionBelow_Delay,
		stCharDelay					
	);

	--type wstate used for writing control machine

	type wstate is (
		stRW,						
		stEnable,					
		stIdle					
	);
	

	--Clock counter
	signal clkCount:std_logic_vector(5 downto 0):= "000000";

	--pulse to enable the writing
	signal activateW:std_logic:= '0';	
	
    --Counter used for timing delays between the states
	signal count:std_logic_vector (16 downto 0):= "00000000000000000";

	--Pulse used to mark when a timing delay ends
	signal delayOK:std_logic:= '0';

	--Microseconds clock
	signal OneUSClk:std_logic;		

	--Used for machine control
	signal stCur:mstate:= stPowerOn_Delay;
	signal stNext:mstate;			  	
	signal stCurW:wstate:= stIdle;
	signal stNextW:wstate;

	--Used to define if either the writing is done or not
	signal writeDone:std_logic:= '0';

	--type array to store display commands
	type LCD_CMDS_T is array(integer range <>) of std_logic_vector(9 downto 0);

	--array used to store the display comands
	constant LCD_CMDS : LCD_CMDS_T := ( 0 => "00"&X"3C",			--Function Set
					    1 => "00"&"00001100",		--Display ON, Cursor OFF, Blink OFF
					    2 => "00"&X"01",			--Clear Display
					    3 => "00"&X"02", 			--return home

					    4 => "10"&X"20",				--space
					    5 => "10"&X"20",				--space

					    6 => "10"&X"53", 				--S
					    7 => "10"&"01110001",  			--q
					    8 => "10"&"01110101",  			--u
					    9 => "10"&"01100001",  			--a
					    10 => "10"&X"72", 				--r
					    11 => "10"&X"65", 				--e
						
					    12 => "10"&X"20",				--space
					    13 => "10"&X"20",				--space

					    14 => "10"&X"44", 				--D
					    15 => "10"&"01100001",  			--a
					    16 => "10"&"01110011",  			--s
					    17 => "10"&"01101000",  			--h

					    18 => "10"&X"20",				--space
					    19 => "10"&X"20",				--space

					    20 => "10"&"01010000", 			--P
					    21 => "10"&X"72", 				--r
					    22 => "10"&X"65", 				--e
					    23 => "10"&"01110011",  			--s
					    24 => "10"&"01110011",  			--s
						
					    25 => "10"&X"20",				--space
					    26 => "10"&X"20",				--space

					    27 => "10"&"01000101", 			--E
					    28 => "10"&"01101110",  			--n
					    29 => "10"&X"74",				--t
					    30 => "10"&X"65", 				--e
					    31 => "10"&X"72", 				--r
					    32 => "00"&"00000010", 			--home
					    33 => "00"&"11000000");			-- Shifts cursor to bottom left


		
	--pointer to get through the array elements											
	signal lcd_cmd_ptr : integer range 0 to LCD_CMDS'HIGH + 1 := 0;
begin
 	
	--This process increments on clkCount, used for oneUSClk control
	process (CLK, oneUSClk)
    		begin
			if (CLK = '1' and CLK'event) then
				clkCount <= clkCount + 1;
			end if;
		end process;

	--microseconds clock pulse
	oneUSClk <= clkCount(5);

	--Microseconds counter process, that resets if the delay is completed
	process (oneUSClk, delayOK)
		begin
			if (oneUSClk = '1' and oneUSClk'event) then
				if delayOK = '1' then
					count <= "00000000000000000";
				else
					count <= count + 1;
				end if;
			end if;
		end process;

	--This goes high when all commands have been run
	writeDone <= '1' when (lcd_cmd_ptr = 33) 
		else '0';

	--Increments the pointer as it goes through the functions commands
	process (lcd_cmd_ptr, oneUSClk)
   		begin
			if (oneUSClk = '1' and oneUSClk'event) then
				if ((stNext = stInitDne or stNext = stDisplayCtrlSet or stNext = stDisplayClear) and writeDone = '0') then 
					lcd_cmd_ptr <= lcd_cmd_ptr + 1;
				elsif stCur = stPowerOn_Delay or stNext = stPowerOn_Delay then
					lcd_cmd_ptr <= 0;
				else
					lcd_cmd_ptr <= lcd_cmd_ptr;
				end if;
			end if;
		end process;
	
	--Logic of when each delay ends, related to each function from the display
	delayOK <= '1' when ((stCur = stPowerOn_Delay and count = "00100111001010010") or 			--20050 us
					(stCur = stFunctionSet_Delay and count = "00000000000110010") or	--50 us
					(stCur = stPositionBelow_Delay and count = "00000000000101000") or	--40 us
					(stCur = stDisplayCtrlSet_Delay and count = "00000000000110010") or	--50 us
					(stCur = stDisplayClear_Delay and count = "00000011001000000") or	--1600 us
					(stCur = stCharDelay and count = "00000000000110010"))			--50 us
		else	'0';
  	
	--Process that runs the state machine
	process (oneUSClk, rst)
		begin
			if oneUSClk = '1' and oneUSClk'Event then
				if rst = '1' then
					stCur <= stPowerOn_Delay;
				else
					stCur <= stNext;
				end if;
			end if;
		end process;

	
	--  This process relates the pin output to each command from the array based on the current state
	process (stCur, delayOK, writeDone, lcd_cmd_ptr)
		begin   
			case stCur is
				-- Startup Delay
				when stPowerOn_Delay =>
					if delayOK = '1' then
						stNext <= stFunctionSet;
					else
						stNext <= stPowerOn_Delay;
					end if;
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';

				--Initialization of the display
				when stFunctionSet =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '1';	
					stNext <= stFunctionSet_Delay;
				
				--Delay of the Initialization
				when stFunctionSet_Delay =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';
					if delayOK = '1' then
						stNext <= stDisplayCtrlSet;
					else
						stNext <= stFunctionSet_Delay;
					end if;
				
				--Defines some configurations of the display (cursor and display functions)
				when stDisplayCtrlSet =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '1';
					stNext <= stDisplayCtrlSet_Delay;

				--Delay of the configurations
				when stDisplayCtrlSet_Delay =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';
					if delayOK = '1' then
						stNext <= stDisplayClear;
					else
						stNext <= stDisplayCtrlSet_Delay;
					end if;
				
				--Clears the display
				when stDisplayClear	=>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '1';
					stNext <= stDisplayClear_Delay;

				--Delay of the display clearing
				when stDisplayClear_Delay =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';
					if delayOK = '1' then
						stNext <= stInitDne;
					else
						stNext <= stDisplayClear_Delay;
					end if;
				
				--Initializing writing
				when stInitDne =>		
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';
					stNext <= stActWr;

				--writing character (activateW pulse was enabled)
				when stActWr =>		
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '1';
					stNext <= stCharDelay;
					
				--Delaying to write the next character
				when stCharDelay =>
					RS <= LCD_CMDS(lcd_cmd_ptr)(9);
					RW <= LCD_CMDS(lcd_cmd_ptr)(8);
					LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
					activateW <= '0';

					--if the first line is done writing, the cursor will start to write the line from beow			
					if (delayOK = '1' and lcd_cmd_ptr = 17) then
						stNext <= stPositionBelow;

					--else continue writing
					elsif delayOK = '1' then
						stNext <= stInitDne;
					else
						stNext <= stCharDelay;
					end if;

				--positions the cursor to the seconds line
				when stPositionBelow =>
					RS <= LCD_CMDS(33)(9);
					RW <= LCD_CMDS(33)(8);
					LCD_DB <= LCD_CMDS(33)(7 downto 0);
					activateW <= '1';					
					stNext <= stPositionBelow_Delay;

				--Delays the cursor repositioning
				when stPositionBelow_Delay =>
					RS <= LCD_CMDS(33)(9);
					RW <= LCD_CMDS(33)(8);
					LCD_DB <= LCD_CMDS(33)(7 downto 0);
					activateW <= '0';					
					if delayOK = '1' then
						stNext <= stInitDne;
					else
						stNext <= stPositionBelow_Delay;
					end if;
			end case;
		end process;		
								   
 	--Writing machine process
	process(oneUSClk, rst)
		begin
			if oneUSClk = '1' and oneUSClk'Event then
				if rst = '1' then
					stCurW <= stIdle;
				else
					stCurW <= stNextW;
				end if;
			end if;
		end process;

	--Machine that controls the writing of the display
	process (stCurW, activateW)
		begin   
		
			case stCurW is
				--This sends the address across the bus telling the DIO5 that we are
				--writing to the LCD
				when stRw =>
					OE <= '0';
					stNextW <= stEnable;
				
				--This adds another clock onto the wait to make sure data is stable on 
				--the bus before enable goes low.
				when stEnable => 
					OE <= '0';
					stNextW <= stIdle;
				
				--Waiting for the write command from the instuction state machine
				when stIdle =>
					OE <= '1';
					if activateW = '1' then
						stNextW <= stRw;
					else
						stNextW <= stIdle;
					end if;
				end case;
		end process;
end Behavioral;

-- ======================================================================
-- game
-- ======================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

--explanation of the pins:
--LCD_DB to OE: Same as described at main.vhd
--rst: used to reset the display in case the player isn't at the game screen
--keyboard_output: pin related to the keyboard up or down state, that defines where
--the character wil be located
--gameover: defines if the player lost the game

entity game is
	Port ( LCD_DB: out std_logic_vector(7 downto 0);
       	RS:out std_logic;
       	RW:out std_logic;
   	CLK:in std_logic;
   	OE:out std_logic;
   	rst:in std_logic;
	keyboard_output:in std_logic;
	gameover:out std_logic);
end game;

architecture Behavioral of game is

    --type mstate is a type used for the display functions manipulation

    type mstate is (   				   
   	 stFunctionSet,   	     		
   	 stDisplayCtrlSet,
   	 stDisplayClear,
   	 stPowerOn_Delay, 				
   	 stFunctionSet_Delay,
   	 stDisplayCtrlSet_Delay,     
   	 stDisplayClear_Delay,
   	 stInitDne,   				
   	 stActWr,
   	 stCharDelay   			
    );
    
    --type mstate_c is a type used for the display functions manipulation, especifically for the character

    type mstate_c is (   				   
   	 stFunctionSet,   	  
   	 stDisplayCtrlSet,
   	 stDisplayClear,
   	 stPowerOn_Delay, 			
   	 stFunctionSet_Delay,
   	 stDisplayCtrlSet_Delay,     
   	 stDisplayClear_Delay,
   	 stInitDne,   
   	 stActWr,
   	 stCharDelay,
   	 stNothing --Write delay for operations
    );

    --type Keystate is used for character position
    
    type Keystate is (
   	 stUp,
   	 stDown
    );

    --type istate used to define either the obstacles or the character is being writen

	type istate is (
   	 stObstacle,
   	 stCharacter
    	);

    --type wstate used for writing control machine

    type wstate is (
   	 stRW, 
   	 stEnable, 
   	 stIdle
    );


    --Clock counter
    signal clkCount:std_logic_vector(5 downto 0):= "000000";

    --pulse to enable the writing
    signal activateW:std_logic:= '0';

    --Counter used for timing delays between the states
    signal count:std_logic_vector (16 downto 0):= "00000000000000000";

    --Pulse used to mark when a timing delay ends
    signal delayOK:std_logic:= '0';

    --Microseconds clock
    signal OneUSClk:std_logic;

    --Used for machine control
    signal stCur:mstate:= stPowerOn_Delay;
    signal stNext:mstate;
    signal stCur_c:mstate_c:= stPowerOn_Delay;
    signal stNext_c:mstate_c;
    signal stCurW:wstate:= stIdle;
    signal stNextW:wstate;
    signal stCurKey:keystate:= stUp;
    signal stNextKey:keystate;
    signal stCurI:istate := stObstacle;
    signal stNextI:istate;

    --Used to define if either the writing is done or not
    signal writeDone:std_logic:= '0';

    --Counters used to timing the obstacles exhibition on the screen
    signal counterSeconds: std_logic_vector (25 downto 0) := "00000000000000000000000000";
    signal counterSeconds2: std_logic_vector (25 downto 0) := "00000000000000000000000000";
    signal counterSeconds3: std_logic_vector (25 downto 0) := "00000000000000000000000000";

    --Defines the obstacles state (cleared, warning, and blast)
    signal state_marker: integer range 0 to 2 := 0;

    --Defines if the blast will appear up or down
    signal flag_updown: std_logic := '0';

    --Counter used to control the number of character writen in the screen
    signal counter: integer range 0 to 22 := 0;

    --slowly incremented used to increase the speed of the obstacles, making the game more difficult and challenging
    signal accelerate: std_logic_vector (25 downto 0) := "00000000000000000000000000";

    --seed used to define the obstacles patern
    signal random_value: std_logic_vector (30 downto 0) := "1001010101110000111101100001001";


    --type array to store display commands
    type LCD_CMDS_T is array(integer range <>) of std_logic_vector(9 downto 0);

    --array used to store the display comands, for the obstacles
    constant LCD_CMDS : LCD_CMDS_T := ( 0 => "00"&X"3C",   		 --Function Set
   				 	1 => "00"&"00001100",   		 --Display ON, Cursor OFF, Blink OFF
   				 	2 => "00"&X"01",   		 --Clear Display
   				 	3 => "00"&X"80",    		 --return home
   				 	4 => "00"&X"8D",

   				 	5 => "10"&"00100001", --!
   				 	6 => "10"&"11111111",
   					  7 => "00"&X"80",
   					  8 => "00"&X"80");


    --array used to store the display comands, for the character					 
    constant LCD_CMDS_c : LCD_CMDS_T := ( 0 => "00"&X"3C",   		 --Function Set
   				 	1 => "00"&"00001100",   		 --Display ON, Cursor OFF, Blink OFF
   				 	2 => "00"&X"01",   		 --Clear Display
   				 	3 => "00"&X"02",    		 --return home
   					 
   					  4 => "10"&"00100000",
   					  5 => "00"&"10000001",   		 -- UP
   					  6 => "10"&"11011011",
   					  7 => "10"&"00100000",
   					  8 => "00"&"11000001",   		 -- DOWN
   					  9 => "10"&"11011011"
   					  );


    --pointer to get through the obstacles array elements												 
    signal lcd_cmd_ptr : integer range 0 to LCD_CMDS'HIGH + 1 := 0;

    --pointer to get through the character array elements
    signal lcd_cmd_ptr_c : integer range 0 to LCD_CMDS_c'HIGH + 1 := 0;
begin
	 

    --activates gameover if the character colides with the blast
    gameover <= '1' when (state_marker = 2 and (keyboard_output = flag_updown)) else
		'0';

    --process used to manipulate the counters used for switching between the obstacles states
    --it also increments accelerate each cycle
    process (CLK, oneUSClk)
   		 begin
   		 if (CLK = '1' and CLK'event) then
   			 clkCount <= clkCount + 1;
				 if(rst = '1') then
					counterSeconds <= "00000000000000000000000000";
   				counterSeconds2 <= "00000000000000000000000000";
					counterSeconds3 <= "00000000000000000000000000";
					accelerate <= "00000000000000000000000000";
					state_marker <= 0;
   			 elsif(counterSeconds < "10111110101111000010000000") then
   				 state_marker <= 0;
					 accelerate <= accelerate;
   				 counterSeconds <= counterSeconds + 1;
   			 else
   				 if(counterSeconds2 >= "10111110101111000010000000") then
   					 if(counterSeconds3 >= "10111110101111000010000000") then
   						 state_marker <= 0;
							 accelerate <= accelerate + "00000000110000000000000000";
   						 counterSeconds <= "00000000000000000000000000" + accelerate;
   						 counterSeconds2 <= "00000000000000000000000000" + accelerate;
   						 counterSeconds3 <= "00000000000000000000000000" + accelerate;
   					 else
   						 state_marker <= 2;
							 accelerate <= accelerate;
   						 counterSeconds <= counterSeconds;
   						 counterSeconds2 <= counterSeconds2;
   						 counterSeconds3 <= counterSeconds3 + 1;
   					 end if;
   				 else
   					 state_marker <= 1;
						 accelerate <= accelerate;
   					 counterSeconds2 <= counterSeconds2 + 1;
   					 counterSeconds3 <= "00000000000000000000000000" + accelerate;
   					 counterSeconds <= counterSeconds;
   				 end if;
   			 end if;
   		 end if;
   	 end process;

    --microseconds clock pulse
    oneUSClk <= clkCount(5);

    --Microseconds counter process, that resets if the delay is completed
    process (oneUSClk, delayOK)
   	 begin
   		 if (oneUSClk = '1' and oneUSClk'event) then
   			 if delayOK = '1' then
   				 count <= "00000000000000000";
   			 else
   				 count <= count + 1;
   			 end if;
   		 end if;
   	 end process;


    --Write is done when the character ends its moving
    writeDone <= '1' when ((lcd_cmd_ptr_c = 6) or (lcd_cmd_ptr_c = 9))
   	 else '0';


    --the process that controls the entire logic of the character and obstacles manipulation
    process (oneUSClk)
  		 begin
   		 if (oneUSClk = '1' and oneUSClk'event) then
			--Each cycle random_value rotates, changing where the obstacles will be shown, either up or down
			random_value <= random_value(29 downto 0) & random_value(30);

				--resets the game
				if rst = '1' then
					counter <= 0;
					lcd_cmd_ptr <= 0;
					lcd_cmd_ptr_c <= 0;
					flag_updown <= '0';

				--If the character is being controlled
				elsif (stCurI = stCharacter) then
				
				--Gets through the array normally
					if ((stNext_c = stInitDne or stNext_c = stDisplayCtrlSet or stNext_c = stDisplayClear) and writeDone = '0') then
						lcd_cmd_ptr_c <= lcd_cmd_ptr_c + 1;
						counter <= counter;

				--Start of the array if getting powered on
					elsif (stCur_c = stPowerOn_Delay or stNext_c = stPowerOn_Delay) then
						lcd_cmd_ptr_c <= 0;
						counter <= counter;

				--If the player switchs to down input, initializes the character writing at the bottom
					elsif ((stCurKey = stUp and keyboard_output = '0' and writeDone = '1' and stCur_c = stNothing)) then
						lcd_cmd_ptr_c <= 4;
						counter <= counter;

				--If the player switchs to up input, initializes the character writing at the top
					elsif ((stCurKey = stDown and keyboard_output = '1' and writeDone = '1' and stCur_c = stNothing)) then
						lcd_cmd_ptr_c <= 7;
						counter <= counter;

				--Control the character positioning after finishing the obstacles writing
				elsif (stCurKey = stDown and counter = 0) then
						lcd_cmd_ptr_c <= 4;
						counter <= 1;
				elsif (stCurKey = stUp and counter = 0) then
						lcd_cmd_ptr_c <= 7;
						counter <= 1;

				--Character is static
					else
						lcd_cmd_ptr_c <= lcd_cmd_ptr_c;
						counter <= counter;
					end if;

				--Obstacles signals are static while character is active
					lcd_cmd_ptr <= lcd_cmd_ptr;
					flag_updown <= flag_updown;

			--If the obstacles are being writen
				else
					--Character signals are static while Obstacles is active
					lcd_cmd_ptr_c <= lcd_cmd_ptr_c;

					--Control Delay
					if (stCur = stPowerOn_Delay or stCur = stFunctionSet_Delay or stCur = stDisplayCtrlSet_Delay) then
							if delayOK = '1' then
							lcd_cmd_ptr <= lcd_cmd_ptr + 1;
							counter <= counter;
							flag_updown <= flag_updown;
							end if;

					--Initializing writing after clearing display
					elsif (stCur = stDisplayClear_Delay and delayOK = '1') then
							lcd_cmd_ptr <= 3;
							counter <= counter;
							flag_updown <= flag_updown;
					else
						case state_marker is
							--display is blank
							when 0 =>
								counter <= 0;
								if((stCur = stCharDelay and lcd_cmd_ptr = 8) or (stCur = stDisplayClear)) then
									if(lcd_cmd_ptr = 8) then
										if((((random_value(30) xor random_value(13)) xor random_value(6)) xor random_value(24)) = '0') then
											flag_updown <= '1';
										else
											flag_updown <= '0';
										end if;
									else
										flag_updown <= flag_updown;
									end if;
									lcd_cmd_ptr <= 2;
								else
									lcd_cmd_ptr <= lcd_cmd_ptr;
									flag_updown <= flag_updown;
								end if;

							--display exibits warning signal "!"
							when 1 =>
									flag_updown <= flag_updown;
									if (stCur = stCharDelay and lcd_cmd_ptr = 3 and delayOK = '1') then
										lcd_cmd_ptr <= 4;
										counter <= 0;
									elsif (stCur = stCharDelay and lcd_cmd_ptr = 4 and delayOK = '1') then
										lcd_cmd_ptr <= 5;
										counter <= 0;
									else
										if(counter < 6) then
											lcd_cmd_ptr <= lcd_cmd_ptr;
											if(stCur = stCharDelay and delayOK = '1') then
												counter <= counter + 1;
											else
												counter <= counter;
											end if;
										else
											lcd_cmd_ptr <= 7;
											counter <= 6;
										end if;
									end if;

							--Laser Blast
							when 2 =>
									flag_updown <= flag_updown;
									if (stCur = stCharDelay and lcd_cmd_ptr = 7 and delayOK = '1' and counter = 6) then
										lcd_cmd_ptr <= 3;
										counter <= counter;
									elsif (stCur = stCharDelay and lcd_cmd_ptr = 3 and delayOK = '1' and counter = 6) then
										lcd_cmd_ptr <= 6;
										counter <= counter;
									else
										if(counter < 22) then
											lcd_cmd_ptr <= lcd_cmd_ptr;
											if(stCur = stCharDelay and delayOK = '1') then
												counter <= counter + 1;
											else
												counter <= counter;
											end if;
										else
											lcd_cmd_ptr <= 8;
											counter <= 22;
										end if;
									end if;
						end case;
					end if;
				end if;
   			 end if;
   	 end process;
    
    --Logic of when each delay ends, related to each function from the display

    delayOK <= '1' when ((stCurI = stObstacle and 
				((stCur = stPowerOn_Delay and count = "00100111001010010") or    		 --20050 us
   				 (stCur = stFunctionSet_Delay and count = "00000000000110010") or    --50 us
   				 (stCur = stDisplayCtrlSet_Delay and count = "00000000000110010") or    --50 us
   				 (stCur = stDisplayClear_Delay and count = "00000011001000000") or    --1600 us
   				 (stCur = stCharDelay and count = "00000000000110010")))
   				 or 
				((stCurI = stCharacter and
   				 ((stCur_c = stPowerOn_Delay and count = "00100111001010010") or    		 --20050 us
   				 (stCur_c = stFunctionSet_Delay and count = "00000000000110010") or    --50 us
   				 (stCur_c = stDisplayCtrlSet_Delay and count = "00000000000110010") or    --50 us
   				 (stCur_c = stDisplayClear_Delay and count = "00000011001000000") or    --1600 us
   				 (stCur_c = stCharDelay and count = "00000000000110010")))))  		 --50 us
   	 else    '0';
      
    --Process that runs the state machines
    process (oneUSClk, rst)
   	 begin
   		 if oneUSClk = '1' and oneUSClk'Event then
   			 if rst = '1' then
   				 stCur_c <= stPowerOn_Delay;
   				 stCurKey <= stUp;
				 stCurI <= stCharacter;
				 stCur <= stPowerOn_Delay;
   			 else
   				 stCurKey <= stNextKey;
   				 stCur_c <= stNext_c;
				 stCurI <= stNextI;
				 stCur <= stNext;
   			 end if;
   		 end if;
   	 end process;
   	
	--Logic of the character position
    stNextKey <= stUp when keyboard_output = '0'
   				 else stDown;

	--Logic of which element is being controlled (obstacles or character)
    stNextI <= stCharacter when ((state_marker = 0 and lcd_cmd_ptr = 3) or (state_marker = 1 and counter = 6))
		else stObstacle;

    
    --  This process relates the pin output to each command from the array based on the current state
    process (stCur, stCur_c, stNext_c, delayOK, writeDone, lcd_cmd_ptr, lcd_cmd_ptr_c, flag_updown, stCurI, keyboard_output)
   	 begin
   	 case stCurI is

		--If character is being controlled
		when stCharacter =>

		stNext <= stCur;
   		 case stCur_c is
   			 -- Startup Delay
   			 when stPowerOn_Delay =>
   				 if delayOK = '1' then
   					 stNext_c <= stFunctionSet;
   				 else
   					 stNext_c <= stPowerOn_Delay;
   				 end if;
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 activateW <= '0';

   			 --Initialization of the display
   			 when stFunctionSet =>
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 activateW <= '1';    
   				 stNext_c <= stFunctionSet_Delay;
   			 
   			 --Delay of the Initialization
   			 when stFunctionSet_Delay =>
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 activateW <= '0';
   				 if delayOK = '1' then
   					 stNext_c <= stDisplayCtrlSet;
   				 else
   					 stNext_c <= stFunctionSet_Delay;
   				 end if;
   			 
   			 --Defines some configurations of the display (cursor and display functions)
   			 when stDisplayCtrlSet =>
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 activateW <= '1';
   				 stNext_c <= stDisplayCtrlSet_Delay;

   			 --Delay of the configurations
   			 when stDisplayCtrlSet_Delay =>
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 activateW <= '0';
   				 if delayOK = '1' then
   					 stNext_c <= stDisplayClear;
   				 else
   					 stNext_c <= stDisplayCtrlSet_Delay;
   				 end if;
   			 
   			 --Clears the display
   			 when stDisplayClear    =>
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 activateW <= '1';
   				 stNext_c <= stDisplayClear_Delay;

   			 --Delay of the display clearing
   			 when stDisplayClear_Delay =>
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 activateW <= '0';
   				 if delayOK = '1' then
   					 stNext_c <= stInitDne;
   				 else
   					 stNext_c <= stDisplayClear_Delay;
   				 end if;
   			 
   			 --Initializing writing
   			 when stInitDne =>   	 
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 activateW <= '0';
   				 stNext_c <= stActWr;

			--writing character (activateW pulse was enabled)
   			 when stActWr =>   	 
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 if lcd_cmd_ptr_c = 6 or lcd_cmd_ptr_c = 9 then
   					 activateW <= '0';
   				 else
   					 activateW <= '1';
   				 end if;
   				 stNext_c <= stCharDelay;
   				 
   			 --Delaying to write the next character
   			 when stCharDelay =>
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 activateW <= '0';   
				 --filters if the square is being written at top or bottom, and keeps the process				 
   				 if delayOK = '1' then
   					 if (lcd_cmd_ptr_c = 5 or lcd_cmd_ptr_c = 8) then
       							 stNext_c <= stDisplayCtrlSet_Delay;
   						 elsif (lcd_cmd_ptr_c = 6 or lcd_cmd_ptr_c = 9) then
       							 stNext_c <= stNothing;
   					 else
   						 stNext_c <= stInitDne;
   					 end if;
   				 else
   					 stNext_c <= stCharDelay;
   				 end if;
   				 
			--Wait and does nothing, unless the player changed the character position
   			 when stNothing =>
   				 RS <= LCD_CMDS_c(lcd_cmd_ptr_c)(9);
   				 RW <= LCD_CMDS_c(lcd_cmd_ptr_c)(8);
   				 LCD_DB <= LCD_CMDS_c(lcd_cmd_ptr_c)(7 downto 0);
   				 activateW <= '0';
   				 if((keyboard_output = '0' and lcd_cmd_ptr_c >= 7) or (keyboard_output = '1' and lcd_cmd_ptr_c <= 6)) then
   					 stNext_c <= stDisplayClear;
   				 else
   					 stNext_c <= stNothing;
   				 end if;
   		 end case;

	--If the obstacles are being written
   	 when stObstacle =>
		stNext_c <= stCur_c;
   		 case stCur is
			 -- Startup Delay
   			 when stPowerOn_Delay =>
   				 if delayOK = '1' then
   					 stNext <= stFunctionSet;
   				 else
   					 stNext <= stPowerOn_Delay;
   				 end if;
   				 RS <= LCD_CMDS(lcd_cmd_ptr)(9);
   				 RW <= LCD_CMDS(lcd_cmd_ptr)(8);
   				 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   				 activateW <= '0';

   			 --Initialization of the display
   			 when stFunctionSet =>
   				 RS <= LCD_CMDS(lcd_cmd_ptr)(9);
   				 RW <= LCD_CMDS(lcd_cmd_ptr)(8);
   				 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   				 activateW <= '1';    
   				 stNext <= stFunctionSet_Delay;
   			 
   			 --Delay of the Initialization
   			 when stFunctionSet_Delay =>
   				 RS <= LCD_CMDS(lcd_cmd_ptr)(9);
   				 RW <= LCD_CMDS(lcd_cmd_ptr)(8);
   				 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   				 activateW <= '0';
   				 if delayOK = '1' then
   					 stNext <= stDisplayCtrlSet;
   				 else
   					 stNext <= stFunctionSet_Delay;
   				 end if;
   			 
   			 --Defines some configurations of the display (cursor and display functions)
   			 when stDisplayCtrlSet =>
   				 RS <= LCD_CMDS(lcd_cmd_ptr)(9);
   				 RW <= LCD_CMDS(lcd_cmd_ptr)(8);
   				 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   				 activateW <= '1';
   				 stNext <= stDisplayCtrlSet_Delay;

   			 --Delay of the configurations
   			 when stDisplayCtrlSet_Delay =>
   				 RS <= LCD_CMDS(lcd_cmd_ptr)(9);
   				 RW <= LCD_CMDS(lcd_cmd_ptr)(8);
   				 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   				 activateW <= '0';
   				 if delayOK = '1' then
   					 stNext <= stDisplayClear;
   				 else
   					 stNext <= stDisplayCtrlSet_Delay;
   				 end if;
   			 
   			 --Clears the display
   			 when stDisplayClear    =>
   				 RS <= LCD_CMDS(lcd_cmd_ptr)(9);
   				 RW <= LCD_CMDS(lcd_cmd_ptr)(8);
   				 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   				 activateW <= '1';
   				 stNext <= stDisplayClear_Delay;

   			 --Delay of the display clearing
   			 when stDisplayClear_Delay =>
   				 RS <= LCD_CMDS(lcd_cmd_ptr)(9);
   				 RW <= LCD_CMDS(lcd_cmd_ptr)(8);
   				 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   				 activateW <= '0';
   				 if delayOK = '1' then
   					 stNext <= stInitDne;
   				 else
   					 stNext <= stDisplayClear_Delay;
   				 end if;
   			 
   			 --Initializing writing
   			 when stInitDne =>   	 
   				 RS <= LCD_CMDS(lcd_cmd_ptr)(9);
   				 RW <= LCD_CMDS(lcd_cmd_ptr)(8);
   				 if(flag_updown = '0') then
   					 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   				 else   	 
   					 if(lcd_cmd_ptr = 3) then
   						 LCD_DB <= X"C0";
   					 elsif(lcd_cmd_ptr = 4) then
   						 LCD_DB <= X"CD";
   					 else
   						 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   					 end if;
   				 end if;
   				 activateW <= '0';
   				 stNext <= stActWr;

			--writing character (activateW pulse was enabled)
   			 when stActWr =>   	 
   				 RS <= LCD_CMDS(lcd_cmd_ptr)(9);
   				 RW <= LCD_CMDS(lcd_cmd_ptr)(8);
   				 if(flag_updown = '0') then
   					 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   				 else   	 
   					 if(lcd_cmd_ptr = 3) then
   						 LCD_DB <= X"C0";
   					 elsif(lcd_cmd_ptr = 4) then
   						 LCD_DB <= X"CD";
   					 else
   						 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   					 end if;
   				 end if;
   				 activateW <= '1';
   				 stNext <= stCharDelay;
   				 
   			 --Delaying to write the next character
   			 when stCharDelay =>
   				 RS <= LCD_CMDS(lcd_cmd_ptr)(9);
   				 RW <= LCD_CMDS(lcd_cmd_ptr)(8);

				 --checks where the obstacles are being written, up or down
   				 if(flag_updown = '0') then
   					 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   				 else   	 
   					 if(lcd_cmd_ptr = 3) then
   						 LCD_DB <= X"C0";
   					 elsif(lcd_cmd_ptr = 4) then
   						 LCD_DB <= X"CD";
   					 else
   						 LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
   					 end if;
   				 end if;
   				 activateW <= '0';   				 
   				 if (delayOK = '1' and lcd_cmd_ptr = 2) then
   					 stNext <= stDisplayClear;
   				 elsif delayOK = '1' then
   					 stNext <= stInitDne;
   				 else
   					 stNext <= stCharDelay;
   				 end if;
   		 	end case;
   		end case;
   	end process;   				 
   							    
	--Writing machine process
    process(oneUSClk, rst)
   	 begin
   		 if oneUSClk = '1' and oneUSClk'Event then
   			 if rst = '1' then
   				 stCurW <= stIdle;
   			 else
   				 stCurW <= stNextW;
   			 end if;
   		 end if;
   	 end process;

    --Machine that controls the writing of the display
    process (stCurW, activateW)
   	 begin   
   		 case stCurW is
			--This sends the address across the bus telling the DIO5 that we are
			--writing to the LCD
   			when stRw =>
           		OE <= '0';
           		stNextW <= stEnable;
           	
			--This adds another clock onto the wait to make sure data is stable on 
			--the bus before enable goes low.
       		when stEnable =>
           		OE <= '1';
           		stNextW <= stIdle;
           	
			--Waiting for the write command from the instuction state machine
       		when stIdle =>
           		OE <= '0';
           		if activateW = '1' then
               		stNextW <= stRw;
           		else
               		stNextW <= stIdle;
           		end if;
   		 end case;
   	 end process;
end Behavioral;

-- ======================================================================
-- gameover
-- ======================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

--explanation of the pins:
--LCD_DB to OE: Same as described at main.vhd
--rst: used to reset the display in case the player isn't at the game over screen

entity gameover is
    Port ( LCD_DB: out std_logic_vector(7 downto 0);
           RS:out std_logic;
           RW:out std_logic;
	   CLK:in std_logic;
	   OE:out std_logic;
	   rst:in std_logic		);
end gameover;

architecture Behavioral of gameover is

	--type mstate is a type used for the display functions manipulation
	type mstate is (					  
		stFunctionSet,		 	
		stDisplayCtrlSet,
		stDisplayClear,
		stPowerOn_Delay,  			
		stFunctionSet_Delay,
		stDisplayCtrlSet_Delay, 	
		stDisplayClear_Delay,
		stInitDne,					
		stActWr,
		stPositionBelow,
		stPositionBelow_Delay,
		stCharDelay	
	);

	--type wstate used for writing control machine
	type wstate is (
		stRW,					
		stEnable,			
		stIdle			
	);
	
	--Clock counter
	signal clkCount:std_logic_vector(5 downto 0):= "000000";

	--pulse to enable the writing
	signal activateW:std_logic:= '0';	
	
	--Counter used for timing delays between the states
	signal count:std_logic_vector (16 downto 0):= "00000000000000000";

	--Pulse used to mark when a timing delay ends
	signal delayOK:std_logic:= '0';		
	
	--Microseconds clock
	signal OneUSClk:std_logic;	
	
	--Used for machine control
	signal stCur:mstate:= stPowerOn_Delay;				
	signal stNext:mstate;			  	
	signal stCurW:wstate:= stIdle; 					
	signal stNextW:wstate;

	--Used to define if either the writing is done or not
	signal writeDone:std_logic:= '0';

	--generic score number (score not finished)
	constant number:std_logic_vector (7 downto 0) := "00111111";

	--score converted to integer
	signal score_total:integer range 0 to 999;

	--score numbers
	signal score_unit, score_dec, score_cent: integer range 0 to 9;

	--score numbers conversion to display code
	signal unit_display, dec_display, cent_display:std_logic_vector (7 downto 0);

	--type array to store display commands
	type LCD_CMDS_T is array(integer range <>) of std_logic_vector(9 downto 0);

	--array used to store the display comands
	constant LCD_CMDS : LCD_CMDS_T := (0 => "00"&X"3C",			--Function Set
					    1 => "00"&"00001100",			--Display ON, Cursor OFF, Blink OFF
					    2 => "00"&X"01",			--Clear Display
					    3 => "00"&X"02", 			--return home

					    4 => "10"&X"20",				--space
					    5 => "10"&X"20",				--space

					    6 => "10"&X"20", 				--space
					    7 => "10"&X"20",  			--space
					    8 => "10"&X"20",  			--space
					    9 => "10"&"01010011",  			--s
					    10 => "10"&"01100011", 				--c
					    11 => "10"&"01101111", 				--o
						
					    12 => "10"&X"72",				--r
					    13 => "10"&X"65",				--e

					    14 => "10"&"00111010", 				--:
						 15 => "10"&X"20",  			--space
						 16 => "10"&X"20",  			--space
						 17 => "10"&X"20",  			--space
						 18 => "10"&X"20",  			--space
						 19 => "10"&X"20",  			--space
						 20 => "10"&X"20",  			--space
						 21 => "10"&X"20",  			--space
						 22 => "10"&X"30",  			--centena
						 23 => "10"&X"30",  			--dezena
						 24 => "10"&X"30",  		--unidade
					    25 => "00"&"00000010", 			--home
					    26 => "00"&"11000000");			-- Shifts cursor to bottom left
						 


	--pointer to get through the array elements													
	signal lcd_cmd_ptr : integer range 0 to LCD_CMDS'HIGH + 1 := 0;

	--current command word: positions 22..24 carry the score digits (signals),
	--so they are selected here instead of inside the constant array
	signal cmd_word : std_logic_vector(9 downto 0);
begin

	cmd_word <= "10"&cent_display when lcd_cmd_ptr = 22 else
	            "10"&dec_display  when lcd_cmd_ptr = 23 else
	            "10"&unit_display when lcd_cmd_ptr = 24 else
	            LCD_CMDS(lcd_cmd_ptr);

	--score numbers logic
	score_total <= conv_integer(number);
	score_cent <= score_total / 100;
	score_dec <= (score_total / 10) rem 10;
	score_unit <= score_total rem 10;
	
	--numbers display conversion (unit)
	unit_display <= "00110000" when (score_unit = 0) 
	else "00110001" when (score_unit = 1)
	else "00110010" when (score_unit = 2)
	else "00110011" when (score_unit = 3)
	else "00110100" when (score_unit = 4)
	else "00110101" when (score_unit = 5)
	else "00110110" when (score_unit = 6)
	else "00110111" when (score_unit = 7)
	else "00111000" when (score_unit = 8)
	else "00111001";
	
	--numbers display conversion (dec)
	dec_display <= "00110000" when (score_dec = 0) 
	else "00110001" when (score_dec = 1)
	else "00110010" when (score_dec = 2)
	else "00110011" when (score_dec = 3)
	else "00110100" when (score_dec = 4)
	else "00110101" when (score_dec = 5)
	else "00110110" when (score_dec = 6)
	else "00110111" when (score_dec = 7)
	else "00111000" when (score_dec = 8)
	else "00111001";
	
	--numbers display conversion (cent)
	cent_display <= "00110000" when (score_cent = 0) 
	else "00110001" when (score_cent = 1)
	else "00110010" when (score_cent = 2)
	else "00110011" when (score_cent = 3)
	else "00110100" when (score_cent = 4)
	else "00110101" when (score_cent = 5)
	else "00110110" when (score_cent = 6)
	else "00110111" when (score_cent = 7)
	else "00111000" when (score_cent = 8)
	else "00111001";
 	
	--This process increments on clkCount, used for oneUSClk control
	process (CLK, oneUSClk)
    		begin
			if (CLK = '1' and CLK'event) then
				clkCount <= clkCount + 1;
			end if;
		end process;

	--microseconds clock pulse
	oneUSClk <= clkCount(5);

	--Microseconds counter process, that resets if the delay is completed
	process (oneUSClk, delayOK)
		begin
			if (oneUSClk = '1' and oneUSClk'event) then
				if delayOK = '1' then
					count <= "00000000000000000";
				else
					count <= count + 1;
				end if;
			end if;
		end process;

	--This goes high when all commands have been run
	writeDone <= '1' when (lcd_cmd_ptr = 25) 
		else '0';

	--This goes high when all commands have been run
	process (lcd_cmd_ptr, oneUSClk)
   		begin
			if (oneUSClk = '1' and oneUSClk'event) then
				if ((stNext = stInitDne or stNext = stDisplayCtrlSet or stNext = stDisplayClear) and writeDone = '0') then 
					lcd_cmd_ptr <= lcd_cmd_ptr + 1;
				elsif stCur = stPowerOn_Delay or stNext = stPowerOn_Delay then
					lcd_cmd_ptr <= 0;
				else
					lcd_cmd_ptr <= lcd_cmd_ptr;
				end if;
			end if;
		end process;
	
	--Logic of when each delay ends, related to each function from the display
	delayOK <= '1' when ((stCur = stPowerOn_Delay and count = "00100111001010010") or 			--20050 us
					(stCur = stFunctionSet_Delay and count = "00000000000110010") or	--50 us
					(stCur = stPositionBelow_Delay and count = "00000000000101000") or	--40 us
					(stCur = stDisplayCtrlSet_Delay and count = "00000000000110010") or	--50 us
					(stCur = stDisplayClear_Delay and count = "00000011001000000") or	--1600 us
					(stCur = stCharDelay and count = "00000000000110010"))			--50 us
		else	'0';
  	
	--Process that runs the state machine
	process (oneUSClk, rst)
		begin
			if oneUSClk = '1' and oneUSClk'Event then
				if rst = '1' then
					stCur <= stPowerOn_Delay;
				else
					stCur <= stNext;
				end if;
			end if;
		end process;

	
	--  This process relates the pin output to each command from the array based on the current state
	process (stCur, delayOK, writeDone, lcd_cmd_ptr, cmd_word)
		begin   
			case stCur is
				-- Startup Delay
				when stPowerOn_Delay =>
					if delayOK = '1' then
						stNext <= stFunctionSet;
					else
						stNext <= stPowerOn_Delay;
					end if;
					RS <= cmd_word(9);
					RW <= cmd_word(8);
					LCD_DB <= cmd_word(7 downto 0);
					activateW <= '0';

				--Initialization of the display
				when stFunctionSet =>
					RS <= cmd_word(9);
					RW <= cmd_word(8);
					LCD_DB <= cmd_word(7 downto 0);
					activateW <= '1';	
					stNext <= stFunctionSet_Delay;
				
				--Delay of the Initialization
				when stFunctionSet_Delay =>
					RS <= cmd_word(9);
					RW <= cmd_word(8);
					LCD_DB <= cmd_word(7 downto 0);
					activateW <= '0';
					if delayOK = '1' then
						stNext <= stDisplayCtrlSet;
					else
						stNext <= stFunctionSet_Delay;
					end if;
				
				--Defines some configurations of the display (cursor and display functions)
				when stDisplayCtrlSet =>
					RS <= cmd_word(9);
					RW <= cmd_word(8);
					LCD_DB <= cmd_word(7 downto 0);
					activateW <= '1';
					stNext <= stDisplayCtrlSet_Delay;

				--Delay of the configurations
				when stDisplayCtrlSet_Delay =>
					RS <= cmd_word(9);
					RW <= cmd_word(8);
					LCD_DB <= cmd_word(7 downto 0);
					activateW <= '0';
					if delayOK = '1' then
						stNext <= stDisplayClear;
					else
						stNext <= stDisplayCtrlSet_Delay;
					end if;
				
				--Clears the display
				when stDisplayClear	=>
					RS <= cmd_word(9);
					RW <= cmd_word(8);
					LCD_DB <= cmd_word(7 downto 0);
					activateW <= '1';
					stNext <= stDisplayClear_Delay;

				--Delay of the display clearing
				when stDisplayClear_Delay =>
					RS <= cmd_word(9);
					RW <= cmd_word(8);
					LCD_DB <= cmd_word(7 downto 0);
					activateW <= '0';
					if delayOK = '1' then
						stNext <= stInitDne;
					else
						stNext <= stDisplayClear_Delay;
					end if;
				
				--Initializing writing
				when stInitDne =>		
					RS <= cmd_word(9);
					RW <= cmd_word(8);
					LCD_DB <= cmd_word(7 downto 0);
					activateW <= '0';
					stNext <= stActWr;

				--writing character (activateW pulse was enabled)
				when stActWr =>		
					RS <= cmd_word(9);
					RW <= cmd_word(8);
					LCD_DB <= cmd_word(7 downto 0);
					activateW <= '1';
					stNext <= stCharDelay;
					
				--Delaying to write the next character
				when stCharDelay =>
					RS <= cmd_word(9);
					RW <= cmd_word(8);
					LCD_DB <= cmd_word(7 downto 0);
					activateW <= '0';					
					if (delayOK = '1' and lcd_cmd_ptr = 14) then
						stNext <= stPositionBelow;
					elsif delayOK = '1' then
						stNext <= stInitDne;
					else
						stNext <= stCharDelay;
					end if;

				--positions the cursor to the seconds line
				when stPositionBelow =>
					RS <= LCD_CMDS(26)(9);
					RW <= LCD_CMDS(26)(8);
					LCD_DB <= LCD_CMDS(26)(7 downto 0);
					activateW <= '1';					
					stNext <= stPositionBelow_Delay;

				--Delays the cursor repositioning
				when stPositionBelow_Delay =>
					RS <= LCD_CMDS(26)(9);
					RW <= LCD_CMDS(26)(8);
					LCD_DB <= LCD_CMDS(26)(7 downto 0);
					activateW <= '0';					
					if delayOK = '1' then
						stNext <= stInitDne;
					else
						stNext <= stPositionBelow_Delay;
					end if;
			end case;
		end process;					
								   
 	--Writing machine process
	process(oneUSClk, rst)
		begin
			if oneUSClk = '1' and oneUSClk'Event then
				if rst = '1' then
					stCurW <= stIdle;
				else
					stCurW <= stNextW;
				end if;
			end if;
		end process;

	--Machine that controls the writing of the display
	process (stCurW, activateW)
		begin   
		
			case stCurW is
				--This sends the address across the bus telling the DIO5 that we are
				--writing to the LCD
				when stRw =>
					OE <= '0';
					stNextW <= stEnable;
				
				--This adds another clock onto the wait to make sure data is stable on 
				--the bus before enable goes low.
				when stEnable => 
					OE <= '0';
					stNextW <= stIdle;
				
				--Waiting for the write command from the instuction state machine
				when stIdle =>
					OE <= '1';
					if activateW = '1' then
						stNextW <= stRw;
					else
						stNextW <= stIdle;
					end if;
				end case;
		end process;
end Behavioral;

-- ======================================================================
-- main (TOP)
-- ======================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

--This is the main code that contains the integration between the three states of the game
--(title screen, game itself, game over screen) and the keyboard.


--Explanation of each pin:
--CLK - Clock from the FGPA, 50MHz frequency
--LCD_DB - A 8-bit vector that contains the 8 LSB of the FGPA display command function.
--RS - A flag related to the display register
--RW - A flag related to the read/write function of the display
--OE - A flag to enable the writing/reading
--ps2_clk - The clock from the keyboard itself
--ps2_data - The serial binary data received from the keyboard

entity main is
    Port ( 
        CLK      : in  std_logic;
        LCD_DB   : out std_logic_vector(7 downto 0);
        RS       : out std_logic;
        RW       : out std_logic;
        OE       : out std_logic;
		  ps2_clk     : in  STD_LOGIC;
		  ps2_data    : in  STD_LOGIC
    );
end main;



architecture Behavioral of main is

--Title Screen from the game component

    component menu
        Port ( clk: in std_logic; rst: in std_logic;
               LCD_DB: out std_logic_vector(7 downto 0);
		RS, RW, OE: out std_logic);
    end component;

--The game itself component

    component game
        Port ( clk: in std_logic; rst: in std_logic;
               LCD_DB: out std_logic_vector(7 downto 0);
		RS, RW, OE: out std_logic;
		keyboard_output:in std_logic;
		gameover:out std_logic);
    end component;

--The game over screen component

    component gameover
        Port ( clk: in std_logic; rst: in std_logic;
               LCD_DB: out std_logic_vector(7 downto 0);
		RS, RW, OE: out std_logic);
    end component;

--The keyboard input logic component
	 
	 component top_keyboard
        Port (clk         : in  STD_LOGIC;
					rst         : in  STD_LOGIC;
					ps2_clk     : in  STD_LOGIC;
					ps2_data    : in  STD_LOGIC;
					keyboard_output : out STD_LOGIC;
					button : out STD_LOGIC);
			end component;

--local signals that are going to be related to its respectives components

    signal menu_db, game_db, gameover_db : std_logic_vector(7 downto 0);
    signal menu_rs, menu_rw, menu_oe : std_logic;
    signal game_rs, game_rw, game_oe : std_logic;
    signal gameover_rs, gameover_rw, gameover_oe : std_logic;

--signal frame will define which screen is the player at the moment
    
    signal frame : integer range 0 to 2 := 0; 

--local signals that are going to be related to its respectives components

    signal rst_game, rst_menu, rst_gameover : std_logic;

--Flag that defines if the player lost the game

    signal gameover_flag : std_logic := '0';

--keyboard_output is related to the square position during the game based on which
--key the player inputed through the keyboard

    signal keyboard_output: std_logic := '0';

--signal related to the "enter" key from the keyboard

    signal button : std_logic;

--reset of the keyboard logic (not used by any button here, kept inactive)

    signal rst : std_logic := '0';

--state between the game screens

    type gamestate is (
	stMenu,
	stGame,
	stGameOver);

    signal stCur: gamestate := stMenu;

begin

--process initialized to define which screen the game will display based on the user interaction
    process(clk)
	begin
		if(rising_edge(clk)) then
			if(button = '0' and stCur = stMenu) then
				stCur <= stMenu;
			elsif((button = '1' and stCur = stMenu) or (stCur = stGame and gameover_flag = '0') or (stCur = stGameOver and button = '1')) then
				stCur <= stGame;
		   	else
				stCur <= stGameOver;
			end if;
		end if;
	end process;

--reset screens that are inactive

    rst_menu <= '0' when (frame = 0) else '1';
    rst_game <= '0' when (frame = 1) else '1';
	 rst_gameover <= '0' when (frame = 2) else '1';

--pinning of the components

    Inst_Menu: menu 
        port map(clk => CLK, rst => rst_menu, LCD_DB => menu_db, RS => menu_rs, RW => menu_rw, OE => menu_oe);

    Inst_Game: game 
        port map(clk => CLK, rst => rst_game, LCD_DB => game_db, RS => game_rs, RW => game_rw, OE => game_oe, keyboard_output => keyboard_output, gameover => gameover_flag);

    Inst_GameOver: gameover
        port map(clk => CLK, rst => rst_gameover, LCD_DB => gameover_db, RS => gameover_rs, RW => gameover_rw, OE => gameover_oe);
		  
	 Inst_keyboard: top_keyboard
        port map(clk => clk, rst => rst, ps2_clk => ps2_clk, ps2_data => ps2_data, keyboard_output => keyboard_output, button => button);

--relating the display pins to the pins of the active screen at the moment

    process(frame, menu_db, menu_rs, menu_rw, menu_oe, game_db, game_rs, game_rw, game_oe, gameover_db, gameover_rs, gameover_rw, gameover_oe)
    begin
        if frame = 0 then
            LCD_DB <= menu_db;
            RS     <= menu_rs;
            RW     <= menu_rw;
            OE     <= menu_oe;
        elsif frame = 1 then
            LCD_DB <= game_db;
            RS     <= game_rs;
            RW     <= game_rw;
            OE     <= game_oe;
	else
	    LCD_DB <= gameover_db;
            RS     <= gameover_rs;
            RW     <= gameover_rw;
            OE     <= gameover_oe;
        end if;
    end process;

--frame logic based on states

    frame <= 0 when (stCur = stMenu) else
	     1 when (stCur = stGame) else
	     2;

end Behavioral;
