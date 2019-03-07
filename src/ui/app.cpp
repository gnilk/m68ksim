
// We have to define this before we include imgui_internal.h to get ImVec2 operators.
#define IMGUI_DEFINE_MATH_OPERATORS

#include <imgui.h>
#include <imgui_internal.h>     // For ImVec2 operators and more.

#include "../simulator.h"
#include "../simhelpers.h"

// Include glfw3.h after our OpenGL definitions
#include <GLFW/glfw3.h> 
#include <OpenGl/glu.h>


#include <stdarg.h>
#include <string.h>
#include <stdint.h>
#include <string>
#include <vector>

#include <fstream>
#include <streambuf>

#include <TextEditor.h>
#include <amiga_hunk_parser.h>
#include "expsolver.h"

static ImVec4 line_col(0.6f,0.2f,0.2f,1.0f);


#define MAX_PC_HISTORY 16

typedef struct
{
    float color;
} Pixel;

static Pixel* pixmap = NULL;
static int pixmap_width = 0;
static int pixmap_height = 0;

static void LoadHunkFile(std::string filename);



class CommandHistory {
public:
    void Push(const char *cmdstring);
private:
    std::vector<std::string> history;
};

class ConsoleBuffer {
public:
    void Printf(const char *format,...);
public:
    std::vector<std::string>history;
};

void CommandHistory::Push(const char *cmdstring) {
    history.push_back(std::string(cmdstring));
    // TODO: Flush history to disk
}



void ConsoleBuffer::Printf(const char *format, ...) {
    va_list values;
    char newstr[1024];

    va_start( values, format );
    vsprintf( newstr, format, values);
    va_end( values);

    history.push_back(std::string(newstr));
}



//------------------------------------------------------------------------------------------------

void gizmo(const char* str_id, ImVec2 &pos, float radius, ImVec2 &minpos, ImVec2 maxpos)
{
    ImVec2 backup_pos = ImGui::GetCursorPos();
    ImGui::SetCursorScreenPos(pos-ImVec2(radius,radius));
    ImGui::InvisibleButton(str_id,ImVec2(2*radius,2*radius));
    ImGui::SetItemAllowOverlap(); // This is to allow having other buttons OVER our gizmo. 

    if (ImGui::IsItemActive())
    {
        pos = ImGui::GetIO().MousePos - GImGui->ActiveIdClickOffset + ImVec2(radius,radius);

        if (pos.x < minpos.x)
            pos.x = minpos.x;
        if (pos.y < minpos.y)
            pos.y = minpos.y;
        if (pos.x >= maxpos.x)
            pos.x = maxpos.x;
        if (pos.y >= maxpos.y)
            pos.y = maxpos.y;
    }

    ImDrawList* draw_list = ImGui::GetWindowDrawList();
    ImU32 col = ImGui::GetColorU32(ImGui::IsItemHovered() ? ImGuiCol_PlotLinesHovered : ImGuiCol_PlotLines);
    draw_list->AddCircle(pos, radius, col);

    ImGui::SetCursorPos(backup_pos);
}

// Memory texture properties
static GLuint memoryTextureID;
static void *textureBuffer = NULL;
static int textureScaling = 2;
static uint32_t memoryTextureAddr = 0;

static PCHistory *history;
static Registers *regs;
static time_t tLastActive;
static char cmdbuffer[256];
static ConsoleBuffer consoleBuffer;
static CommandHistory commandHistory;
static uint32_t memoryViewAddr = 0;
static SourceLineDebug *sourceLineDebug;
static uint32_t runToPCEquals = 0;


int AppInit(int argc, char **argv) {
    FILE* fhandle;

    if(argc != 2)
    {
        printf("Usage: sim <program file>\n");
        return 0;
    }





    sim_begin();

    LoadHunkFile(argv[1]);

    sim_begin();

    // AHPInfo *ahp = sim_loadhunkfile(argv[1]);
    // if (ahp == NULL) {
    //     return NULL;
    // }

    // // Try to resolve source line debugging
    // sourceLineDebug = SourceLineDebug::FromAHP(ahp);
    // history = new PCHistory(MAX_PC_HISTORY, sourceLineDebug);
    // regs = new Registers();
    // PCHistory history(MAX_PC_HISTORY);
    // Registers regs;


    glGenTextures(1, &memoryTextureID);
    glBindTexture(GL_TEXTURE_2D, memoryTextureID);
    glPixelStorei( GL_UNPACK_ALIGNMENT, 1 );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );

    // Must be configurable
    textureBuffer = sim_romptr(memoryTextureAddr);



    return 1;

}


static void ShowMemoryDump() {
    ImGui::Begin("MemoryView", nullptr, ImVec2(640,360));
    ImGui::Text("Memory from: $%.8x", memoryViewAddr);

    uint8_t *ptrRom = (uint8_t *)sim_ramptr(0);

    uint32_t ofs = memoryViewAddr;
    // Scaling options???
    char line[256];
    for (int nLines = 0; nLines < 32; nLines++) {
        line[0]='\0';
        for(int i=0;i<16;i++) {
            snprintf(line, 256, "%s %.2x", line, ptrRom[ofs++]);
        }
        ImGui::Text("$%.8x | %s", ofs - 16, line);
    }
    ImGui::End();

}

static void ShowMemoryTexture() {
//    IMGUI_API void          Image(ImTextureID user_texture_id, const ImVec2& size, const ImVec2& uv0 = ImVec2(0,0), const ImVec2& uv1 = ImVec2(1,1), const ImVec4& tint_col = ImVec4(1,1,1,1), const ImVec4& border_col = ImVec4(0,0,0,0));

    textureBuffer = sim_ramptr(memoryTextureAddr);

    glBindTexture(GL_TEXTURE_2D, memoryTextureID);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, 320, 180, 0, GL_RED, GL_UNSIGNED_BYTE, textureBuffer);

    ImTextureID id = (ImTextureID)memoryTextureID;
    ImGui::Begin("MemoryTexture", nullptr, ImVec2(640,360));
    ImGui::Text("Memory from: $%.8x [scale: x%d]", memoryTextureAddr, textureScaling);
    // Scaling options???
    ImGui::Image((void*)memoryTextureID, ImVec2(320 * textureScaling,180 * textureScaling));
    ImGui::End();
}


static void ShowStack() {

    ImTextureID id = (ImTextureID)memoryTextureID;
    uint32_t stackCurrent = sim_stack_addr();
    uint32_t stack_top = sim_stack_top();

    ImGui::Begin("Stack", nullptr, ImVec2(180,360));
    ImGui::Text("Stack at: $%.8x", sim_stack_addr());
    while(stackCurrent < stack_top) {
        uint32_t v = cpu_read_long(stackCurrent); //0x0003fffc);
        ImGui::Text("$%.8x: $%.8x", stackCurrent, v);
        stackCurrent+=4;
    }
    ImGui::End();
}

static void ShowRegisters() {
    std::vector<std::string> data;
    std::vector<std::string> addr;

    regs->Print(data, addr);

    ImGui::Begin("Registers", nullptr, ImVec2(400,200));
    ImGui::Columns(2);
    for(int i=0;i<data.size();i++) {
        ImGui::Text("%s",data[i].c_str());
        ImGui::NextColumn();
        ImGui::Text("%s",addr[i].c_str());
        ImGui::NextColumn();
    }
    ImGui::Columns(1);
    ImGui::Separator();

    uint32_t pc = m68k_get_reg(NULL,M68K_REG_PC);        /* Program Counter */
    uint32_t sr = m68k_get_reg(NULL,M68K_REG_SR);        /* Status Register */
    ImGui::Text("SR: $%.8x", sr);
    ImGui::Text("PC: $%.8x", pc);
    ImGui::End();       
}





static void LoadHunkFile(std::string filename) {

    AHPInfo *ahp = sim_loadhunkfile(filename.c_str());
    if (ahp == NULL) {
        consoleBuffer.Printf("Failed to load: %s", filename.c_str());        
        return ;
    }

    // Try to resolve source line debugging
    sourceLineDebug = SourceLineDebug::FromAHP(ahp);
    history = new PCHistory(MAX_PC_HISTORY, sourceLineDebug);
    regs = new Registers();

    // if (!sim_loadhunkfile(filename.c_str())) {
    //     consoleBuffer.Printf("Failed to load: %s", filename.c_str());
    //     return;        
    // }

    consoleBuffer.Printf("Ok, new file loaded: %s", filename.c_str());

}

static char *num2bin(unsigned int num, char *buffer, int maxlen) {
    int idxStart = 0;

    int i=0;
    for (i=31;i>=0;i--) {
        int bit = (num & (1<<i));
        if (bit != 0) break;
    }
    buffer[idxStart]='0';
    idxStart++;
    for(;i>=0;i--) {
        buffer[idxStart] = (num & (1<<i))?'1':'0';
        idxStart++;
    }
    buffer[idxStart]='\0';
    return buffer;
}

static uint32_t ResolveSymbol(std::string name) {
    return sim_addrforsymbol(name.c_str());
}

static void ParseCommands(std::vector<std::string> &args) {

    for(int i=0;i<args.size();i++) {
        printf("%d: %s\n", i, args[i].c_str());
    }

    if (args[0] == std::string("mt")) {
        if (args.size() != 2) {
            consoleBuffer.Printf("Error: Wrong number of arguments!\n");
            consoleBuffer.Printf("Use: mt <addr>\n");
            return;            
        }
        double tmp;
        memoryTextureAddr = ResolveSymbol(args[1]);
        if (memoryTextureAddr == 0) {
            if (gnilk::ExpSolver::Solve(&tmp, args[1].c_str())) {
                memoryTextureAddr = (uint32_t)tmp;
            }            
        }
        return;
    } 

    if (args[0] == std::string("m")) {
        if (args.size() != 2) {
            consoleBuffer.Printf("Error: Wrong number of arguments!\n");
            consoleBuffer.Printf("Use: m <addr>\n");
            return;            
        }
        memoryViewAddr = ResolveSymbol(args[1]);
    
        if (memoryViewAddr == 0) {
            double tmp;
            if (gnilk::ExpSolver::Solve(&tmp, args[1].c_str())) {
                memoryViewAddr = (uint32_t)tmp;
            }

        }        
        return;
    } 


    if ((args[0] == std::string("o")) || (args[0] == std::string("open"))) {
        if (args.size() != 2) {
            consoleBuffer.Printf("Error: Wrong number of arguments!");
            consoleBuffer.Printf("Use: open <filename>");
            return;
        }
        LoadHunkFile(args[1]);
        return;
    }

    if ((args[0] == std::string("sym")) || (args[0] == std::string("symbols"))) {
        if (args.size() != 1) {
            consoleBuffer.Printf("Error: Wrong number of arguments!");
            consoleBuffer.Printf("Use: sym");
            return;            
        }
        // TODO: list symbols
    }

    if ((args[0] == std::string("j")) || (args[0] == std::string("jump"))) {
        if (args.size() != 2) {
            consoleBuffer.Printf("Error: Wrong number of arguments!");
            consoleBuffer.Printf("Use: jump <address>");
            return;
        }
        double tmp;
        uint32_t addr;
        addr = ResolveSymbol(args[1]);

        if (addr == 0) {
            if (!gnilk::ExpSolver::Solve(&tmp, args[1].c_str())) {
                consoleBuffer.Printf("Error: can't resolve '%s'", args[1].c_str());
                return;
            } else {
                addr = (unsigned int)tmp;
            }
        }
        m68k_set_reg(M68K_REG_PC, addr);
        history->FillFrom(m68k_get_reg(NULL, M68K_REG_PC));
        return;
    }

    if (args[0] == std::string("sr")) {
        if (args.size() != 3) {
            consoleBuffer.Printf("Error: Wrong number of arguments!\n");
            consoleBuffer.Printf("Use: sr <reg> <value>\n");
            return;
        }

        m68k_register_t reg;
        if (!RegisterFromString(args[1], reg)) {
            consoleBuffer.Printf("Error: no such register '%s'!\n", args[1].c_str());
            consoleBuffer.Printf("Supported: d0..d7, a0..a7 (all lower case)\n");
            return;
        }

        double tmp;
        if (gnilk::ExpSolver::Solve(&tmp, args[2].c_str())) {
            //memoryTextureAddr = (uint32_t)tmp;
            m68k_set_reg(reg, (unsigned int)tmp);
        }
        return;
    } 

    if (args[0] == std::string("rt")) {
        if (args.size() != 2) {
            consoleBuffer.Printf("Error: Wrong number of arguments!\n");
            consoleBuffer.Printf("Use: rt <value>\n");
            return;
        }

        double tmp;
        uint32_t addr;
        addr = ResolveSymbol(args[1]);
        if (addr == 0) {
            if (!gnilk::ExpSolver::Solve(&tmp, args[1].c_str())) {
                consoleBuffer.Printf("Error: can't resolve '%s'", args[1].c_str());
                return;
            }
            addr = (unsigned int)tmp;
        }
        runToPCEquals = addr;
        return;
    } 

    if (args[0] == std::string("?")) {
        consoleBuffer.Printf("<ret>          step (execute one instruction)\n");
        consoleBuffer.Printf("rt <sym/addr>  Run to symbol or address\n");
        consoleBuffer.Printf("sr <reg> <val> Set Register\n");
        consoleBuffer.Printf("j <sym/addr>   Jump to symbol or address (alias for 'jump')\n");
        consoleBuffer.Printf("m <sym/addr>   Memory view at address or Symbol\n");
        consoleBuffer.Printf("mt <sym/addr>  Memory Texture at address or Symbol\n");
        consoleBuffer.Printf("<expr>         Solve the expression, like: 4+4\n");
        consoleBuffer.Printf("---- Not well tested stuff\n");
        consoleBuffer.Printf("o <file>       LoadHunkFile\n");
        consoleBuffer.Printf("sym            List symbols (not implemented)\n");

        return;
    }

    // Just run this through the expression solver
    double tmp;        
    char binary[48];
    bool bRes = gnilk::ExpSolver::Solve(&tmp, args[0].c_str());
    if (bRes) {
        num2bin((int)tmp, binary, 48);
        consoleBuffer.Printf("> %d, 0x%.x, %%%s\n",(int)tmp,(int)tmp, binary);
    }
}

static bool ProcessCommand(const char *cmdstr) {

    if (strlen(cmdstr)>0) {
        std::vector<std::string> args;
        strutil::split(args, cmdstr, ' ');
        // Push to both history and console
        commandHistory.Push(cmdstr);    // This goes on the history buffer
        consoleBuffer.Printf("%s", cmdstr);  
        ParseCommands(args);
        // Just update the registers since we might have modified them
        regs->UpdateFromSimulator();
        return true;
    }

    return false;
}

static bool IsComment(std::string &str) {
    if (str.length() < 16) return false;
    std::string cpy(str.begin()+16, str.end());
    strutil::trim(cpy);
    if ((cpy.length() > 0) && (cpy[0]==';')) {
        return true;
    }
    return false;
}

static void StepExecution() {
    // Perfor step in simulator
    sim_step();
    // Update registry and history/disasm buffer
    regs->UpdateFromSimulator();
    history->Add(m68k_get_reg(NULL, M68K_REG_PC));
    // This will restore focus to input box
    tLastActive = 0;
}

static void ShowMainWindow() {
    std::vector<std::string> disasm;

    history->Disasm(disasm);
    ImGui::Begin("Disasm", nullptr, ImVec2(1200,800));

    if (ImGui::InputText("Cmd", cmdbuffer, IM_ARRAYSIZE(cmdbuffer), ImGuiInputTextFlags_EnterReturnsTrue)) {
        printf("Process command: %s\n", cmdbuffer);
        if (!ProcessCommand(cmdbuffer)) {
            StepExecution();
        }
        cmdbuffer[0]='\0';
    }

    if (runToPCEquals > 0) {
        uint32_t pcCurrent = m68k_get_reg(NULL, M68K_REG_PC);
        // Finished???
        if (pcCurrent == runToPCEquals) {
            runToPCEquals = 0;
            // Refill history buffer from new position
            history->FillFrom(m68k_get_reg(NULL, M68K_REG_PC));
        } else {
            printf("RT, current: %.8x, dst: %.8x\n", pcCurrent, runToPCEquals);
            StepExecution();
        }

    } 
    ImGui::SetItemDefaultFocus();
    if (ImGui::IsWindowFocused()) {
        if (!ImGui::IsItemActive()) {
            time_t tNow;
            ::time(&tNow);
            if ((tNow - tLastActive) > 2) {
                ImGui::SetKeyboardFocusHere(-1);
                tLastActive = tNow;

            }
        }
    }


    for(int i=0;i<disasm.size();i++) {
        if (IsComment(disasm[i])) {
            ImGui::TextColored(ImColor(128,128,128), "%s", disasm[i].c_str());
        } else {
            ImGui::TextColored(ImColor(255,255,255), "%s",disasm[i].c_str());
        }
    }
    ImGui::Separator();
    for (int i=0;i<consoleBuffer.history.size();i++) {
        ImGui::Text("%s",consoleBuffer.history[i].c_str());    
    }
    
    ImGui::End();   
}

static TextEditor editor;
static const char* fileToEdit = "../src/hello.s";
static void ShowEditor() {
    ImGui::Begin("EditorWindow");
    editor.Render("TextEditor");    
    ImGui::End();
}

void AppRun()
{
    // {
    //         std::ifstream t(fileToEdit);
    //         if (t.good())
    //         {
    //             std::string str((std::istreambuf_iterator<char>(t)), std::istreambuf_iterator<char>());
    //             editor.SetText(str);
    //         }
    // }    
    // ShowEditor();
    ShowRegisters();
    ShowMemoryTexture();
    ShowStack();
    ShowMemoryDump();
    ShowMainWindow();
    // Create a small window containing editable parameters.
    // ImGui::Begin("Parameters",nullptr,ImVec2(200,400));
    // ImGui::InputScalar("Scale", ImGuiDataType_U32, &scale);
    // ImGui::InputFloat2("Start", line_start_pos, 1);
    // ImGui::InputFloat2("End", line_end_pos, 1);
    // ImGui::End();

/*
    ImGui::Begin("Line Study",nullptr,ImVec2(400,400));
    ImDrawList* draw_list = ImGui::GetWindowDrawList();
    ImU32 grid_col = ImGui::GetColorU32(ImGuiCol_Separator);
    ImVec2 old_pos = ImGui::GetCursorScreenPos();

    if (scale < 2)
        scale = 2;
    if (scale > 100)
        scale = 100;

    ImVec2 size = ImGui::GetContentRegionAvail();
    float w = ImFloor(size.x / scalef);
    float h = ImFloor(size.y / scalef);
    ImVec2 dx(scalef,0);
    ImVec2 dy(0,scalef);
    ImVec2 xx(w*scalef,0);
    ImVec2 yy(0,h*scalef);

    // [Re]create the pixmap if it's needed.
    if (w != pixmap_width || h != pixmap_height)
    {
        pixmap = (Pixel*) realloc(pixmap, w*h*sizeof(Pixel));
        pixmap_width = w;
        pixmap_height = h;
    }

    // Clear the pixmap colors.
    for(int i=0 ; i<w*h ; i++)
        pixmap[i].color = 0.0f;

    // Render the horizontal grid lines.
    ImVec2 p = old_pos;
    for (int y=0 ; y<=h ; y++)
    {
        draw_list->AddLine(p, p+xx, grid_col);
        p += dy;
    }

    // Render the vertical grid lines.
    p = old_pos;
    for (int x=0 ; x<=w ; x++)
    {
        draw_list->AddLine(p, p+yy, grid_col);
        p += dx;
    }

    drawLine();

    int wi = (int) w;
    int hi = (int) h;

    // Render the enlarged pixmap.
    for (int y=0 ; y<hi ; y++)
    {
        for (int x=0 ; x<wi ; x++)
        {
            if (pixmap[y*wi+x].color > 0.0f)
            {
                float c = pixmap[y*wi+x].color;
                ImU32 col = ImGui::GetColorU32(ImVec4(line_col.x*c, line_col.y*c, line_col.z*c, 1.0f));
                draw_list->AddRectFilled(old_pos+ImVec2(x*scalef+1.0f, y*scalef+1.0f), old_pos+ImVec2((x+1)*scalef-0.0f, (y+1)*scalef-0.0f), col);
            }
        }
    }

    ImVec2 p0 = old_pos + ImVec2(line_start_pos[0]*scalef, line_start_pos[1]*scalef);
    ImVec2 p1 = old_pos + ImVec2(line_end_pos[0]*scalef, line_end_pos[1]*scalef);
    float radius = 5.0f;
    ImU32 line_col = ImGui::GetColorU32(ImGuiCol_Separator);

    draw_list->AddLine(p0, p1, line_col);

    //
    // Render the line end gizmos the user can move around and update the positions if they
    // have been moved.
    //

    gizmo("##gizmo0", p0, radius, old_pos, old_pos+size);
    gizmo("##gizmo1", p1, radius, old_pos, old_pos+size);

    line_start_pos[0] = (p0.x - old_pos.x)/scalef;
    line_start_pos[1] = (p0.y - old_pos.y)/scalef;

    line_end_pos[0] = (p1.x - old_pos.x)/scalef;
    line_end_pos[1] = (p1.y - old_pos.y)/scalef;

    ImGui::End();
    */
}
