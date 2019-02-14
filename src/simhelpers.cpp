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

#include <amiga_hunk_parser.h>

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


static AHPSection* ahp_getcodesection(AHPInfo *ahp) {
	for (int i = 0; i < ahp->sectionCount; ++i) {
		AHPSection* section = &ahp->sections[i];
		if (section->type == AHPSectionType_Code) {
			return section; 
		}
	}
	return NULL;
}


SourceLineDebug::SourceLineDebug() {

}
// Static
SourceLineDebug *SourceLineDebug::FromAHP(AHPInfo *ahp) {
	AHPSection *code = ahp_getcodesection(ahp);
	if (code == NULL) {
		printf("SourceLineDebug::FromAHP, code section not found\n");
		return NULL;
	} 
	if (code->debugLines == NULL) {
		printf("SourceLineDebug::FromAHP, no debug line info in code section\n");
		return NULL;
	}
	SourceLineDebug * sld = new SourceLineDebug();

	for(int i=0;i<code->debugLineCount;i++) {
		AHPLineInfo *dbgLine = &code->debugLines[i];
		sld->ParseAHPLineInfo(code, dbgLine);
	}
	return sld;
}

static FILE *tryOpen(char *path, const char *filename) {
	char buffer[256];
	snprintf(buffer, 256, "%s/%s", path, filename);
	return fopen(buffer, "r");
}

/*
typedef struct AHPLineInfo
{
	const char* filename;
	int count;

	uint32_t baseOffset;

	uint32_t* addresses;
	int* lines;

} AHPLineInfo;

*/

int SourceLineDebug::GetAHPLineInfoFromSrcLine(AHPLineInfo *lineInfo, int srcLine) {
	for (int i=0;i<lineInfo->count;i++) {
		if (lineInfo->lines[i] == srcLine) {
			return i;
		}
	}
	return -1;
}

void SourceLineDebug::ParseAHPLineInfo(AHPSection *section, AHPLineInfo *lineInfo) {
	// Try load...
	FILE *f = tryOpen(".",lineInfo->filename);
	if (f == NULL) {
		f = tryOpen("..",lineInfo->filename);
		if (f == NULL) {
			// TODO: add specific search paths to some kind of config
			printf("FAILED TO OPEN: %s\n", lineInfo->filename);
		}
	}
	printf("Source file: %s opened, mapped line: %d\n", lineInfo->filename, lineInfo->count);

	int dbgLineCount = 0;
	int lineCount = 0;
	char buffer[1024];
	while(fgets(buffer,1024,f) != NULL) {
		uint32_t addr = 0;
		uint32_t pc_addr = 0;
		std::string str(buffer);

		int idxLineInfo = GetAHPLineInfoFromSrcLine(lineInfo, lineCount+1);
		if (idxLineInfo > -1) {
			addr = lineInfo->addresses[idxLineInfo];
			pc_addr = sim_AHPSectionOffsetToAddr(section, addr);		
		} 
		
		// if ((lineCount+1) == lineInfo->lines[dbgLineCount]) {
		// 	addr = lineInfo->addresses[dbgLineCount];
		// 	pc_addr = sim_AHPSectionOffsetToAddr(section, addr);
		// 	dbgLineCount++;
		// }
		SourceLineItem *item = new SourceLineItem();

		item->srcString = std::string(buffer);
		strutil::rtrim(item->srcString);
		item->srcLine = lineCount;
		item->addr = addr;
		item->pc_addr = pc_addr;

		printf("%d, $%.8x: %s\n", item->srcLine, item->pc_addr, item->srcString.c_str());

		lineItems.push_back(item);

		lineCount++;
	}
	fclose(f);

}

SourceLineItem *SourceLineDebug::GetItem(uint32_t pc_addr) {
	for(int i=0;i<lineItems.size();i++) {
		if (lineItems[i]->pc_addr == pc_addr) {
			return lineItems[i];
		}
	}
	return NULL;
}
SourceLineItem *SourceLineDebug::GetItemFromSrcLine(uint32_t srcLine) {
	for (int i=0;i<lineItems.size();i++) {
		if (lineItems[i]->srcLine == srcLine) {
			return lineItems[i];
		}
	}
	return NULL;
}


#define MAX_PC_HISTORY 16



PCHistory::PCHistory(int maxitems, 	SourceLineDebug *sld /* = NULL */) {
	this->maxitems = maxitems;
	this->sourceLineDebug = sld;
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

	//
	// TODO: Revisit this one!
	//


	if ((pc >= items[0].pc) && (pc <= items[maxitems/2].pc)) {
		// we are within first portion of window range, do nothing
		//printf("Within first portion of window range..\n");
		return;
	}

	//printf("At end, pc: %.4x, first: %.4x: mid pc: %.4x\n",pc, items[0].pc, items[MAX_PC_HISTORY/2].pc);

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
	} else if (pc < items[0].pc) {
		//printf("Long jump before, we are not within window");
		FillFrom(pc);
		return;
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

//
// TODO: This should NOT return list of strings but rather a list of structured line-items which can be formatted
//       properly by the UI
//
void PCHistory::Disasm(std::vector<std::string> &outstrings) {
	static char buff[100];
	static char buff2[100];
	static unsigned int instr_size;

	uint32_t current_pc = m68k_get_reg(NULL, M68K_REG_PC);

	uint32_t prevSrcLine = 0;

	SourceLineItem *lineDebugItem = NULL;
	char line[256];

	for (int i=0;i<(next+1);i++) {
		uint32_t pc = items[i].pc;
		//printf("Disasm, pc: %x\n", pc);	

		const char *symbol = sim_symbolforaddr(pc);

		if (symbol != NULL) {
			outstrings.push_back(std::string(symbol));
		}

		lineDebugItem = NULL;
		if (sourceLineDebug != NULL) {
			lineDebugItem = sourceLineDebug->GetItem(pc);
			// if (lineDebugItem != NULL) {
			// 	printf("%.4x : %s\n", pc, lineDebugItem->srcString.c_str());
			// } else {
			// 	printf("Missing sld for: %.4x\n", pc);
			// }
		}


		instr_size = m68k_disassemble(buff, pc, M68K_CPU_TYPE_68000);
		make_hex(buff2, pc, instr_size);
		if (pc == current_pc) {
			snprintf(line, 256, "-> E %03x: %-20s: %s\n", pc, buff2, buff);
		} else {
			snprintf(line, 256, "   E %03x: %-20s: %s\n", pc, buff2, buff);
		}

		std::string outline;
		if (lineDebugItem != NULL) {
			char srcLine[256];

			// Did we miss source lines???
			if ((prevSrcLine > 0) && ((lineDebugItem->srcLine - prevSrcLine) > 1)) {
				// Need to fill in extra lines here
				//printf("currentLine: %d, prev: %d, missing: %d\n", lineDebugItem->srcLine, prevSrcLine, lineDebugItem->srcLine - prevSrcLine);
				for(uint32_t i=prevSrcLine+1; i<lineDebugItem->srcLine;i++) {
					SourceLineItem *item = sourceLineDebug->GetItemFromSrcLine(i);
					//printf("Fetching: %d:%d, %s\n", i, item->srcLine, item->srcString.c_str());
					//                      01234567890123456
					snprintf(srcLine, 256, "         :%.4d|  %s%s",
						item->srcLine,
						"  ",
						item->srcString.c_str());

					outstrings.push_back(std::string(srcLine));
//					printf("  %s\n", srcLine);
				}
			}

			snprintf(srcLine, 256, "$%.8x:%.4d|  %s%s",
				pc, 
				lineDebugItem->srcLine,
				(pc == current_pc)?"->":"  ",
				lineDebugItem->srcString.c_str());

			outline = std::string(srcLine);		
			// Store this, to identify gaps	
			prevSrcLine = lineDebugItem->srcLine;
		} else {
			outline = std::string(line);
		}
		outstrings.push_back(outline);
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

