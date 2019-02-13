#ifndef __SIMHELPERS_H__
#define __SIMHELPERS_H__

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

static const std::string glbRegnames[]={"d0","d1","d2","d3","d4","d5","d6","d7","a0","a1","a2","a3","a4","a5","a6","a7"};

bool RegisterFromString(std::string reg, m68k_register_t &outreg);


class Register {
public:
	Register(m68k_register_t _reg);
	void Update();
	const std::string &Name() const {
		return glbRegnames[reg - (int)M68K_REG_D0];
	}
	std::string Value() {
		return strutil::to_string(value);
	}
	bool IsChanged() {
		return changed;
	}
public:
	m68k_register_t reg;
	uint32_t value;
	uint32_t prev_value;
	bool changed;

};

class Registers {
public:
	Registers();
	void Initialize();
	void UpdateFromSimulator();
	void Print();
	void Print(std::vector<std::string> &data, std::vector<std::string> &addr);
public:
	std::vector<Register> dataRegisters;
	std::vector<Register> addressRegisters;
};

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
	void Disasm(std::vector<std::string> &outstrings);
public:
	std::vector<PCHistoryItem> items;
	uint32_t last;
	int next;
	int maxitems;
protected:
	char buff[100];

};

#endif