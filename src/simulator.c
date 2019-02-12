#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <time.h>

#include "m68k.h"
#include "simulator.h"

/* Data */
unsigned int g_quit = 0;                        /* 1 if we want to quit */
unsigned int g_nmi = 0;                         /* 1 if nmi pending */

int          g_input_device_value = -1;         /* Current value in input device */

unsigned int g_output_device_ready = 0;         /* 1 if output device is ready */
time_t       g_output_device_last_output;       /* Time of last char output */

unsigned int g_int_controller_pending = 0;      /* list of pending interrupts */
unsigned int g_int_controller_highest_int = 0;  /* Highest pending interrupt */

unsigned char g_rom[MAX_ROM+1];                 /* ROM */
unsigned char g_ram[MAX_RAM+1];                 /* RAM */
unsigned int  g_fc;                             /* Current function code from CPU */



/* Exit with an error message.  Use printf syntax. */
void exit_error(char* fmt, ...)
{
	static int guard_val = 0;
	char buff[100];
	unsigned int pc;
	va_list args;

	if(guard_val)
		return;
	else
		guard_val = 1;

	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	fprintf(stderr, "\n");
	pc = m68k_get_reg(NULL, M68K_REG_PPC);
	m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
	fprintf(stderr, "At %04x: %s\n", pc, buff);

	exit(EXIT_FAILURE);
}

/* Read data from RAM, ROM, or a device */
unsigned int cpu_read_byte(unsigned int address)
{
	if(g_fc & 2)	/* Program */
	{
		if(address > MAX_ROM)
			exit_error("Attempted to read byte from ROM address %08x", address);
		return READ_BYTE(g_rom, address);
	}

	/* Otherwise it's data space */
	switch(address)
	{
		case INPUT_ADDRESS:
			return input_device_read();
		case OUTPUT_ADDRESS:
			return output_device_read();
		default:
			break;
	}
	if(address > MAX_RAM)
		exit_error("Attempted to read byte from RAM address %08x", address);
		return READ_BYTE(g_ram, address);
}

unsigned int cpu_read_word(unsigned int address)
{
	if(g_fc & 2)	/* Program */
	{
		if(address > MAX_ROM)
			exit_error("Attempted to read word from ROM address %08x", address);
		return READ_WORD(g_rom, address);
	}

	/* Otherwise it's data space */
	switch(address)
	{
		case INPUT_ADDRESS:
			return input_device_read();
		case OUTPUT_ADDRESS:
			return output_device_read();
		default:
			break;
	}
	if(address > MAX_RAM)
		exit_error("Attempted to read word from RAM address %08x", address);
		return READ_WORD(g_ram, address);
}

unsigned int cpu_read_long(unsigned int address)
{
	printf("cpu_read_long: $%.8x\n", address);
	if(g_fc & 2)	/* Program */
	{
		if(address > MAX_ROM)
			exit_error("Attempted to read long from ROM address %08x", address);
		return READ_LONG(g_rom, address);
	}

	/* Otherwise it's data space */
	switch(address)
	{
		case INPUT_ADDRESS:
			return input_device_read();
		case OUTPUT_ADDRESS:
			return output_device_read();
		default:
			break;
	}
	if(address > MAX_RAM)
		exit_error("Attempted to read long from RAM address %08x", address);
		return READ_LONG(g_ram, address);
}


unsigned int cpu_read_word_dasm(unsigned int address)
{
	if(address > MAX_ROM)
		exit_error("Disassembler attempted to read word from ROM address %08x", address);
	return READ_WORD(g_rom, address);
}

unsigned int cpu_read_long_dasm(unsigned int address)
{
	if(address > MAX_ROM)
		exit_error("Dasm attempted to read long from ROM address %08x", address);
	return READ_LONG(g_rom, address);
}


/* Write data to RAM or a device */
void cpu_write_byte(unsigned int address, unsigned int value)
{
	if(g_fc & 2)	/* Program */
		exit_error("Attempted to write %02x to ROM address %08x", value&0xff, address);

	/* Otherwise it's data space */
	switch(address)
	{
		case INPUT_ADDRESS:
			input_device_write(value&0xff);
			return;
		case OUTPUT_ADDRESS:
			output_device_write(value&0xff);
			return;
		default:
			break;
	}
	if(address > MAX_RAM)
		exit_error("Attempted to write %02x to RAM address %08x", value&0xff, address);
	WRITE_BYTE(g_ram, address, value);
}

void cpu_write_word(unsigned int address, unsigned int value)
{
	if(g_fc & 2)	/* Program */
		exit_error("Attempted to write %04x to ROM address %08x", value&0xffff, address);

	/* Otherwise it's data space */
	switch(address)
	{
		case INPUT_ADDRESS:
			input_device_write(value&0xffff);
			return;
		case OUTPUT_ADDRESS:
			output_device_write(value&0xffff);
			return;
		default:
			break;
	}
	if(address > MAX_RAM)
		exit_error("Attempted to write %04x to RAM address %08x", value&0xffff, address);
	WRITE_WORD(g_ram, address, value);
}

void cpu_write_long(unsigned int address, unsigned int value)
{
	if(g_fc & 2)	/* Program */
		exit_error("Attempted to write %08x to ROM address %08x", value, address);

	/* Otherwise it's data space */
	switch(address)
	{
		case INPUT_ADDRESS:
			input_device_write(value);
			return;
		case OUTPUT_ADDRESS:
			output_device_write(value);
			return;
		default:
			break;
	}
	if(address > MAX_RAM)
		exit_error("Attempted to write %08x to RAM address %08x", value, address);
	WRITE_LONG(g_ram, address, value);
}

/* Called when the CPU pulses the RESET line */
void cpu_pulse_reset(void)
{
	nmi_device_reset();
	output_device_reset();
	input_device_reset();
}

/* Called when the CPU changes the function code pins */
void cpu_set_fc(unsigned int fc)
{
	g_fc = fc;
}

/* Called when the CPU acknowledges an interrupt */
int cpu_irq_ack(int level)
{
	switch(level)
	{
		case IRQ_NMI_DEVICE:
			return nmi_device_ack();
		case IRQ_INPUT_DEVICE:
			return input_device_ack();
		case IRQ_OUTPUT_DEVICE:
			return output_device_ack();
	}
	return M68K_INT_ACK_SPURIOUS;
}




/* Implementation for the NMI device */
void nmi_device_reset(void)
{
	g_nmi = 0;
}

void nmi_device_update(void)
{
	if(g_nmi)
	{
		g_nmi = 0;
		int_controller_set(IRQ_NMI_DEVICE);
	}
}

int nmi_device_ack(void)
{
	printf("\nNMI\n");fflush(stdout);
	int_controller_clear(IRQ_NMI_DEVICE);
	return M68K_INT_ACK_AUTOVECTOR;
}


/* Implementation for the input device */
void input_device_reset(void)
{
	g_input_device_value = -1;
	int_controller_clear(IRQ_INPUT_DEVICE);
}

void input_device_update(void)
{
	if(g_input_device_value >= 0)
		int_controller_set(IRQ_INPUT_DEVICE);
}

int input_device_ack(void)
{
	return M68K_INT_ACK_AUTOVECTOR;
}

unsigned int input_device_read(void)
{
	int value = g_input_device_value > 0 ? g_input_device_value : 0;
	int_controller_clear(IRQ_INPUT_DEVICE);
	g_input_device_value = -1;
	return value;
}

void input_device_write(unsigned int value)
{
}


/* Implementation for the output device */
void output_device_reset(void)
{
	g_output_device_last_output = time(NULL);
	g_output_device_ready = 0;
	int_controller_clear(IRQ_OUTPUT_DEVICE);
}

void output_device_update(void)
{
	if(!g_output_device_ready)
	{
		if((time(NULL) - g_output_device_last_output) >= OUTPUT_DEVICE_PERIOD)
		{
			g_output_device_ready = 1;
			int_controller_set(IRQ_OUTPUT_DEVICE);
		}
	}
}

int output_device_ack(void)
{
	return M68K_INT_ACK_AUTOVECTOR;
}

unsigned int output_device_read(void)
{
	int_controller_clear(IRQ_OUTPUT_DEVICE);
	return 0;
}

void output_device_write(unsigned int value)
{
	char ch;
	if(g_output_device_ready)
	{
		ch = value & 0xff;
		printf("%c", ch);
		g_output_device_last_output = time(NULL);
		g_output_device_ready = 0;
		int_controller_clear(IRQ_OUTPUT_DEVICE);
	}
}


/* Implementation for the interrupt controller */
void int_controller_set(unsigned int value)
{
	unsigned int old_pending = g_int_controller_pending;

	g_int_controller_pending |= (1<<value);

	if(old_pending != g_int_controller_pending && value > g_int_controller_highest_int)
	{
		g_int_controller_highest_int = value;
		m68k_set_irq(g_int_controller_highest_int);
	}
}

void int_controller_clear(unsigned int value)
{
	g_int_controller_pending &= ~(1<<value);

	for(g_int_controller_highest_int = 7;g_int_controller_highest_int > 0;g_int_controller_highest_int--)
		if(g_int_controller_pending & (1<<g_int_controller_highest_int))
			break;

	m68k_set_irq(g_int_controller_highest_int);
}

//
// My interface starts here
//

void cpu_instr_callback()
{
/* The following code would print out instructions as they are executed */
	static char buff[100];
//	static char buff2[100];
	static unsigned int pc;
	static unsigned int instr_size;

	pc = m68k_get_reg(NULL, M68K_REG_PC);
	instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);

	// make_hex(buff2, pc, instr_size);
	// printf("E %03x: %-20s: %s\n", pc, buff2, buff);
	// fflush(stdout);
}


// sim_loadfile, loads a binary (code) file to memory and set up the stack and jump address correctly
int sim_loadfile(const char *filename) {
	FILE* fhandle;

	if((fhandle = fopen(filename, "rb")) == NULL)
		return 0;

	if(fread(&g_rom[8], 1, MAX_ROM+1, fhandle) <= 0)
		return 0;


	// Layout:
	//   0..4: offset stack pointer
	//   4..8: offset program start (this just points to next)
	WRITE_LONG(g_rom, 0, MAX_RAM);	// Stack at this RAM address
	WRITE_LONG(g_rom, 4, 8);

	return 1;
}

//
// sim_begin, initializes the simulator
//
int sim_begin() {
	m68k_init();
	m68k_set_cpu_type(M68K_CPU_TYPE_68000);
	m68k_pulse_reset();
	input_device_reset();
	output_device_reset();
	nmi_device_reset();	
	return 1;
}

int sim_step() {
	m68k_execute(1);	
	return 1;
}

int sim_send() {
	return 1;
}

