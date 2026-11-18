// Emulate the USB endpoint to check packet packing and failure cleanup without
// changing a physical mouse. Compile with the same Apple frameworks as vigilctl.
#define main vigil_cli_main
#include "vigilctl.c"
#undef main
#include <assert.h>

static unsigned char registers[2][128];
static int bank, unlock, entered, commits, fail_index=-1;
static IOReturn fake_request(void *self, IOUSBDevRequestTO *r) {
    (void)self;
    if(r->wIndex==fail_index) { fail_index=-1; return kIOReturnIOError; }
    assert(r->bmRequestType==0x40 || r->bmRequestType==0xc0);
    r->wLenDone=r->wLength;
    if(r->bmRequestType==0xc0) {
        assert(r->bRequest==1 && r->wValue==0x100 && r->wLength==1);
        *(unsigned char *)r->pData=registers[bank][r->wIndex&127]; return 0;
    }
    assert(r->wLength==0);
    if(r->bRequest==6) { assert(r->wValue==0 && r->wIndex==0);entered=0;commits++;return 0; }
    assert(r->bRequest==1);
    if(r->wValue==0) {entered=1;return 0;}
    assert(entered && r->wValue==0x100);
    if((r->wIndex&255)==127) { bank=r->wIndex>>8;assert(bank<2);return 0; }
    if(!bank && (r->wIndex&255)==9) {unlock=(r->wIndex>>8)==0x5a;return 0;}
    assert(unlock);
    registers[bank][r->wIndex&127]=r->wIndex>>8; return 0;
}
int main(void) {
    IOUSBDeviceInterface table={0}; table.DeviceRequestTO=fake_request;
    IOUSBDeviceInterface *pointer=&table; device=&pointer;
    unsigned char expected[]={0,128,3,133,75,175,39,111,67,32,65,232,69,36,66};
    memcpy(registers[1],expected,sizeof(expected));registers[0][2]=2;
    unsigned char result[15]={0};int active=0;
    assert(readsettings(result,&active));
    assert(active==3 && !session && !bank && !unlock && !entered && commits==1);
    for(int i=1;i<15;i++) assert(result[i]==expected[i]);
    assert(begin());assert(writereg(3,0x87));assert(registers[1][3]==0x87);
    assert(registers[1][2]==3 && registers[1][4]==75);
    assert(end());assert(!bank && !unlock && !entered);
    // Partial session entry must still restore bank0, protection, and mode.
    error_text[0]=0;fail_index=0x2009;
    assert(!begin()); assert(session);assert(end());
    assert(!session && !bank && !unlock && !entered);
    assert(strstr(error_text,"USB request failed"));
    int n;assert(!number("800junk",200,3200,&n));assert(!number("-1",0,15,&n));
    assert(number("3200",200,3200,&n) && n==3200);
    assert(ratebyte(1000)==2 && ratebyte(750)==-1);
    assert(known_action(232) && !known_action(255));
    puts("PASS: USB packets, profile reads, register isolation, partial-session cleanup, input validation.");
    return 0;
}
