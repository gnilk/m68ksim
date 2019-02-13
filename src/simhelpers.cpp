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

// see m68k.h - line: 93 for the enum declaration
//static const std::string glbRegnames[]={"d0","d1","d2","d3","d4","d5","d6","d7","a0","a1","a2","a3","a4","a5","a6","a7"};
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


bool RegisterFromString(std::string reg, m68k_register_t &outreg) {
	for (int i=0;i<sizeof(glbRegnames);i++) {
		if (reg == glbRegnames[i]) {
			outreg =  (m68k_register_t)(i + (int)M68K_REG_D0);
			return true;
		}
	}
	return false;
}



Register::Register(m68k_register_t _reg) :
	reg(_reg) {

}
void Register::Update() {
	prev_value = value;
	value = m68k_get_reg(NULL, reg);
	if (value != prev_value) {
		changed = true;
	} else {
		changed = false;
	}
}



Registers::Registers() {
	Initialize();
}
void Registers::Initialize() {
	dataRegisters.push_back(Register(M68K_REG_D0));
	dataRegisters.push_back(Register(M68K_REG_D1));
	dataRegisters.push_back(Register(M68K_REG_D2));
	dataRegisters.push_back(Register(M68K_REG_D3));
	dataRegisters.push_back(Register(M68K_REG_D4));
	dataRegisters.push_back(Register(M68K_REG_D5));
	dataRegisters.push_back(Register(M68K_REG_D6));
	dataRegisters.push_back(Register(M68K_REG_D7));


	addressRegisters.push_back(Register(M68K_REG_A0));
	addressRegisters.push_back(Register(M68K_REG_A1));
	addressRegisters.push_back(Register(M68K_REG_A2));
	addressRegisters.push_back(Register(M68K_REG_A3));
	addressRegisters.push_back(Register(M68K_REG_A4));
	addressRegisters.push_back(Register(M68K_REG_A5));
	addressRegisters.push_back(Register(M68K_REG_A6));
	addressRegisters.push_back(Register(M68K_REG_A7));
}

void Registers::UpdateFromSimulator() {
	for(auto &r : dataRegisters) {
		r.Update();
	}
	for(auto &r : addressRegisters) {
		r.Update();
	}
}

void Registers::Print(std::vector<std::string> &data, std::vector<std::string> &addr) {
	char buffer[256];
	for(auto &r : dataRegisters) {
		snprintf(buffer, 256, "%s:%c%s",r.Name().c_str(), r.IsChanged()?'*':' ',r.Value().c_str());
		data.push_back(std::string(buffer));
	}
	for(auto &r : addressRegisters) {
		snprintf(buffer, 256, "%s:%c%s",r.Name().c_str(), r.IsChanged()?'*':' ',r.Value().c_str());
		addr.push_back(std::string(buffer));
	}
}


void Registers::Print() {
	for(auto &r : dataRegisters) {
		printf("%s:%c%s, ",r.Name().c_str(), r.IsChanged()?'*':' ',r.Value().c_str());
	}
	printf("\n");
	for(auto &r : addressRegisters) {
		printf("%s:%c%s, ",r.Name().c_str(), r.IsChanged()?'*':' ',r.Value().c_str());
	}
	printf("\n");
}


#define MAX_PC_HISTORY 16



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

void PCHistory::Disasm(std::vector<std::string> &outstrings) {
	static char buff[100];
	static char buff2[100];
	static unsigned int instr_size;

	uint32_t current_pc = m68k_get_reg(NULL, M68K_REG_PC);

	char line[256];

	for (int i=0;i<(next+1);i++) {
		uint32_t pc = items[i].pc;
		const char *symbol = sim_symbolforaddr(pc);
		// if (symbol != NULL) {
		// 	printf("SYMBOL: %.8x : %s\n", pc, symbol);
		// }
		instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
		make_hex(buff2, pc, instr_size);
		if (pc == current_pc) {
			snprintf(line, 256, "-> E %03x: %-20s: %s\n", pc, buff2, buff);
//			printf("-> E %03x: %-20s: %s\n", pc, buff2, buff);
		} else {
			snprintf(line, 256, "   E %03x: %-20s: %s\n", pc, buff2, buff);
//			printf("   E %03x: %-20s: %s\n", pc, buff2, buff);
		}
		if (symbol != NULL) {
			outstrings.push_back(std::string(symbol));
		}
		outstrings.push_back(std::string(line));
		fflush(stdout);
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

