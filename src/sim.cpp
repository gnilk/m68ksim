#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <time.h>
#include <vector>
#include "simulator.h"
#include "sim.h"
#include "m68k.h"
#include "osd.h"

void disassemble_program();


/* Disassembler */
void make_hex(char* buff, unsigned int pc, unsigned int length)
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

static void dump_registers() {
	//uint32_t d0 = m68k_get_reg(NULL, M68K_REG_D0);
	const char *d_regnames[]={"d0","d1","d2","d3","d4","d5","d6","d7"};
	const char *a_regnames[]={"a0","a1","a2","a3","a4","a5","a6","a7"};
	for (int i=	M68K_REG_D0;i<=M68K_REG_D7;i++) {
		uint32_t reg = m68k_get_reg(NULL, (m68k_register_t)i);		
		printf("%s: $%.8x, ",d_regnames[i - M68K_REG_D0], reg);
	}	
	printf("\n");
	for (int i=	M68K_REG_A0;i<=M68K_REG_A7;i++) {
		uint32_t reg = m68k_get_reg(NULL, (m68k_register_t)i);		
		printf("%s: $%.8x, ",a_regnames[i - M68K_REG_A0], reg);
	}	
	printf("\n");
}

class PCHistoryItem {
public:
	uint32_t pc;
	// TODO: State's
};
class PCHistory {
public:
	PCHistory(int maxitems);
	void Initialize();
	void FillFrom(uint32_t pc);
	uint32_t NextRelative(uint32_t pc);
	void Add(uint32_t pc);
	void Disasm();
public:
	std::vector<PCHistoryItem> items;
	uint32_t last;
	int next;
	int maxitems;
protected:
	char buff[100];

};
PCHistory::PCHistory(int maxitems) {
	this->maxitems = maxitems;
	Initialize();
}

void PCHistory::Initialize() {
	items.reserve(maxitems);
	for(int i=0;i<maxitems;i++) {
		items[i].pc = 0;
	}
	last = 0;
	next = 0;

	FillFrom(m68k_get_reg(NULL, M68K_REG_PC));

}

void PCHistory::FillFrom(uint32_t frompc) {
	uint32_t pc =  m68k_get_reg(NULL, M68K_REG_PC);
	uint32_t instr_size;
	for (int i=0;i<maxitems;i++) {
		items[i].pc = pc;
		next = i;
		last = pc;

		instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
		pc += instr_size;
	}
}

uint32_t PCHistory::NextRelative(uint32_t pc) {
	char buff[100];
	uint32_t instr_size;
	instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
	pc += instr_size;
	return pc;	
}

void PCHistory::Add(uint32_t pc) {

	if (next == (maxitems-1)) {

		if ((pc >= items[0].pc) && (pc <= items[maxitems/2].pc)) {
			// we are within first portion of window range, do nothing
//			printf("Within first portion of window range..\n");
			return;
		}

//		printf("At end, mid pc: %.4x\n",pc_history.pc[MAX_PC_HISTORY/2]);

		if (pc >= items[maxitems/2].pc) {
			if (pc > items[1 + maxitems/2].pc) {
				// long jump, refill from PC
				// pc_history_init();
				FillFrom(pc);
				return;
			} else {
				//printf("scroll + add\n");	
				for(int i=1;i<maxitems;i++) {
					items[i-1].pc = items[i].pc;
				}
				items[maxitems-1].pc = NextRelative(items[maxitems-2].pc);
				return;
			}
		}
	}

	items[next].pc = pc;
	last = pc;
	next++;
	if (next > (maxitems -1)) {
		next = maxitems - 1;

		// for(int i=1;i<MAX_PC_HISTORY;i++) {
		// 	pc_history.pc[i-1] = pc_history.pc[i];
		// }
	}
}

void PCHistory::Disasm() {
	static char buff[100];
	static char buff2[100];
	static unsigned int instr_size;

	uint32_t current_pc = m68k_get_reg(NULL, M68K_REG_PC);

	for (int i=0;i<(next+1);i++) {
		uint32_t pc = items[i].pc;
		instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
		make_hex(buff2, pc, instr_size);
		if (pc == current_pc) {
			printf("-> E %03x: %-20s: %s\n", pc, buff2, buff);

		} else {
			printf("   E %03x: %-20s: %s\n", pc, buff2, buff);
		}
		fflush(stdout);
	}
}



#define MAX_PC_HISTORY 16
typedef struct PC_HISTORY PC_HISTORY;
struct PC_HISTORY {
	uint32_t pc[MAX_PC_HISTORY];
	uint32_t last;
	int next;
};

static PC_HISTORY pc_history;

static void pc_history_fill(uint32_t frompc);
static void pc_history_add(uint32_t pc);


static void pc_history_init() {
	for(int i=0;i<MAX_PC_HISTORY;i++) {
		pc_history.pc[i] = 0;
	}
	pc_history.last = 0;
	pc_history.next = 0;

	pc_history_fill(m68k_get_reg(NULL, M68K_REG_PC));
}

static void pc_history_fill(uint32_t frompc) {
	// now fill buffer
	static char buff[100];

	uint32_t pc =  m68k_get_reg(NULL, M68K_REG_PC);
	uint32_t instr_size;
	for (int i=0;i<MAX_PC_HISTORY;i++) {
		pc_history.pc[i] = pc;
		pc_history.next = i;
		pc_history.last = pc;

		instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
		pc += instr_size;

	}

}

static uint32_t pc_next_relative(uint32_t pc) {
	static char buff[100];
	uint32_t instr_size;
	instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
	pc += instr_size;
	return pc;	
}
static void pc_history_add(uint32_t pc) {

	if (pc_history.next == (MAX_PC_HISTORY-1)) {

		if ((pc >= pc_history.pc[0]) && (pc <= pc_history.pc[MAX_PC_HISTORY/2])) {
			// we are within first portion of window range, do nothing
//			printf("Within first portion of window range..\n");
			return;
		}

//		printf("At end, mid pc: %.4x\n",pc_history.pc[MAX_PC_HISTORY/2]);

		if (pc >= pc_history.pc[MAX_PC_HISTORY/2]) {
			if (pc > pc_history.pc[1 + MAX_PC_HISTORY/2]) {
				// long jump, refill from PC
				// pc_history_init();
				pc_history_fill(pc);
				return;
			} else {
				//printf("scroll + add\n");	
				for(int i=1;i<MAX_PC_HISTORY;i++) {
					pc_history.pc[i-1] = pc_history.pc[i];
				}
				pc_history.pc[MAX_PC_HISTORY-1] = pc_next_relative(pc_history.pc[MAX_PC_HISTORY-2]);
				return;
			}
		}
	}

	pc_history.pc[pc_history.next] = pc;
	pc_history.last = pc;
	pc_history.next++;
	if (pc_history.next > (MAX_PC_HISTORY -1)) {
		pc_history.next = MAX_PC_HISTORY - 1;

		// for(int i=1;i<MAX_PC_HISTORY;i++) {
		// 	pc_history.pc[i-1] = pc_history.pc[i];
		// }
	}
}

static void disasm_with_history() {
	static char buff[100];
	static char buff2[100];
	static unsigned int instr_size;

	uint32_t current_pc = m68k_get_reg(NULL, M68K_REG_PC);

	for (int i=0;i<(pc_history.next+1);i++) {
		uint32_t pc = pc_history.pc[i];
		instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
		make_hex(buff2, pc, instr_size);
		if (pc == current_pc) {
			printf("-> E %03x: %-20s: %s\n", pc, buff2, buff);

		} else {
			printf("   E %03x: %-20s: %s\n", pc, buff2, buff);
		}
		fflush(stdout);
	}
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

//	pc_history_init();

	char buffer[256];
	int bExecute = TRUE;
	bool bQuit = false;
	while(!bQuit)
	{
		// Our loop requires some interleaving to allow us to update the
		// input, output, and nmi devices.
		//get_user_input();

		// Values to execute determine the interleave rate.
		// Smaller values allow for more accurate interleaving with multiple
		// devices/CPUs but is more processor intensive.
		// 100000 is usually a good value to start at, then work from there.

		// Note that I am not emulating the correct clock speed!
		//m68k_execute(100000);
		dump_registers();
		//pc_history_add(m68k_get_reg(NULL, M68K_REG_PC));
		history.Add(m68k_get_reg(NULL, M68K_REG_PC));
		history.Disasm();
		
		//disasm_with_history();
		//disasm_next();
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
			case 's' : // step
				bExecute = TRUE;
				break;
			case 'd' : // disasm
				disasm(10);
				break;
			case 'r' : 
				dump_registers();
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
		}

		// output_device_update();
		// input_device_update();
		// nmi_device_update();
	}

	return 0;
}

