#ifndef AMIGA_HUNK_PARSER_
#define AMIGA_HUNK_PARSER_

#include <stdint.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

typedef enum AHPSectionTarget
{
	AHPSectionTarget_Any,
	AHPSectionTarget_Fast,
	AHPSectionTarget_Chip,
} AHPSectionTarget;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

typedef enum AHPSectionType
{
	AHPSectionType_Code,
	AHPSectionType_Data,
	AHPSectionType_Bss,
} AHPSectionType;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

typedef struct AHPSymbolInfo
{
	const char* name;
	uint32_t address;

} AHPSymbolInfo;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

typedef struct AHPLineInfo
{
	const char* filename;
	int count;

	uint32_t baseOffset;

	uint32_t* addresses;
	int* lines;

} AHPLineInfo;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

typedef struct AHPSection
{
    AHPSectionType type;
    AHPSectionTarget target;

    int memSize;
    int dataSize; 

    uint32_t dataStart;
    uint32_t relocStart;

    int relocCount;
    int symbolCount;
    int debugLineCount;

    AHPSymbolInfo* symbols;
    AHPLineInfo* debugLines;

} AHPSection;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

typedef struct AHPInfo
{
	AHPSection* sections; 
	int sectionCount;

	size_t fileSize;	// [2019-02-13, Gnilk], added
	void* fileData;	// the loaded file, some of the hunk data points into this or has offsets to it
	void* privateData; // internal state, hands off!

} AHPInfo;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

AHPInfo* ahp_parse_file(const char* filename);

void ahp_print_info(AHPInfo* info, int verbose);
void ahp_free(AHPInfo* info);

#ifdef __cplusplus
}
#endif


#endif

