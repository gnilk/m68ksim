#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <time.h>
#include <string>
#include <vector>
#include "simulator.h"
#include "m68k.h"
#include "osd.h"
#include "strutil.h"
#include "simhelpers.h"


void disassemble_program();


#define MAX_PC_HISTORY 16

/* Disassembler */
static void make_hex(char* buff, unsigned int pc, unsigned int length)
{
	char* ptr = buff;

	for(;length>0;length -= 2)
	{
		sprintf(ptr, "%04x", cpu_read_word_dasm(pc));
		pc += 2;
		ptr += 4;
		if(length > 2)
			*ptr++ = ' ';
	}
}

void disassemble_program()
{
	unsigned int pc;
	unsigned int instr_size;
	char buff[100];
	char buff2[100];

	pc = cpu_read_long_dasm(4);

	while(pc <= 0x16e)
	{
		instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
		make_hex(buff2, pc, instr_size);
		printf("%03x: %-20s: %s\n", pc, buff2, buff);
		pc += instr_size;
	}
	fflush(stdout);
}


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

void disasm_next() {
	static char buff[100];
	static char buff2[100];
	static unsigned int pc;
	static unsigned int instr_size;

	pc = m68k_get_reg(NULL, M68K_REG_PC);
	instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
	make_hex(buff2, pc, instr_size);
	printf("E %03x: %-20s: %s\n", pc, buff2, buff);
	fflush(stdout);
}

void disasm(int nLines) {
	static char buff[100];
	static char buff2[100];
	static unsigned int pc;
	static unsigned int instr_size;

	// Start disasm here
	pc =  m68k_get_reg(NULL, M68K_REG_PC);
	for (int i=0;i<nLines;i++) {
		instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
		make_hex(buff2, pc, instr_size);
		printf("E %03x: %-20s: %s\n", pc, buff2, buff);
		fflush(stdout);
		pc += instr_size;
	}
}

#define TRUE 1
#define FALSE 0

/* The main loop */
int main(int argc, char* argv[])
{
	FILE* fhandle;

	if(argc != 2)
	{
		printf("Usage: sim <program file>\n");
		exit(-1);
	}
	if (!sim_loadfile(argv[1])) {
		exit_error("Unable to open %s", argv[1]);		
	}



	sim_begin();

	PCHistory history(MAX_PC_HISTORY);
	Registers regs;

//	pc_history_init();

	char buffer[256];
	int bExecute = TRUE;
	bool bQuit = false;
	while(!bQuit)
	{
		regs.Print();
		history.Add(m68k_get_reg(NULL, M68K_REG_PC));
		history.Disasm();

		//
		// TODO:
		//  run_to <address>, run to specific address before breaking execution
		//	break_at <address>, set break point at specific address (possible to load/save these from file)
		//  reload, reload same binary - DONT change CPU states
		//  step-back, step one (or more instructions) back
		//  mem <address>,<len>  dump memory at address
		//  fill <address>,<len>,<val>  fill memory at address
		//  
		//  and probably a bunch of other things...  but that would be a good start...
		//

		bExecute = FALSE;
		fgets(buffer, 256, stdin);
		switch(buffer[0]) {
			case 'q' :
				bQuit = true;
				break;
			// NOT NEEDED!!!
			case 's' : // step
				bExecute = TRUE;
				break;
			case 'd' : // disasm
				disasm(10);
				break;
			case 'r' : 
				regs.Print();
				break;
			case 'h' :
				printf("Help:\n");
				printf("  q - quit\n");
				printf("  s - step 1 instruction\n");
				printf("  d - disasm next 10 lines\n");
				printf("  r - registers\n");				
				break;
			default:
				bExecute = TRUE;
		}

		if (bExecute) {
			sim_step();
			regs.UpdateFromSimulator();
		}

		// output_device_update();
		// input_device_update();
		// nmi_device_update();
	}

	return 0;
}

