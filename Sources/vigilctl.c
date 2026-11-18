#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

static IOUSBDeviceInterface **device;
static int session;
static char error_text[256];
static int transfer(unsigned char type, unsigned char request, unsigned short value,
                    unsigned short index, void *data, unsigned short length) {
    IOUSBDevRequestTO r = {0};
    r.bmRequestType=type; r.bRequest=request; r.wValue=value; r.wIndex=index;
    r.wLength=length; r.pData=data; r.noDataTimeout=1500; r.completionTimeout=2000;
    IOReturn rc=(*device)->DeviceRequestTO(device, &r);
    if(rc || r.wLenDone!=length) {
        snprintf(error_text,sizeof(error_text),"USB request failed (0x%08x, index 0x%04x, received %u/%u bytes).",rc,index,(unsigned)r.wLenDone,length);
        return 0;
    }
    if(type==0x40) usleep(20000);
    return 1;
}
static int out(unsigned short index) {return transfer(0x40,1,0x100,index,NULL,0);}
static int readreg(unsigned char reg, unsigned char *v) {return transfer(0xc0,1,0x100,reg,v,1);}
static int writereg(unsigned char reg,unsigned char v) {return out(((unsigned short)v<<8)|reg);}
static int connect_mouse(void) {
    CFMutableDictionaryRef match=IOServiceMatching(kIOUSBDeviceClassName);
    int vid=0x093a,pid=0x2533;
    CFNumberRef v=CFNumberCreate(NULL,kCFNumberIntType,&vid),p=CFNumberCreate(NULL,kCFNumberIntType,&pid);
    CFDictionarySetValue(match,CFSTR(kUSBVendorID),v); CFDictionarySetValue(match,CFSTR(kUSBProductID),p);
    CFRelease(v); CFRelease(p);
    io_iterator_t iter=0; IOReturn rc=IOServiceGetMatchingServices(kIOMainPortDefault,match,&iter);
    if(rc) {snprintf(error_text,sizeof(error_text),"Cannot enumerate USB devices (0x%08x).",rc); return 0;}
    io_service_t service=IOIteratorNext(iter); IOObjectRelease(iter);
    if(!service) {snprintf(error_text,sizeof(error_text),"Canyon mouse not connected (093a:2533). Reconnect it and click Read mouse."); return 0;}
    IOCFPlugInInterface **plugin=NULL; SInt32 score=0;
    rc=IOCreatePlugInInterfaceForService(service,kIOUSBDeviceUserClientTypeID,kIOCFPlugInInterfaceID,&plugin,&score);
    IOObjectRelease(service);
    if(rc || !plugin) {snprintf(error_text,sizeof(error_text),"macOS denied USB access (0x%08x). Run the app outside the development sandbox.",rc); return 0;}
    HRESULT hr=(*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),(LPVOID *)&device);
    (*plugin)->Release(plugin);
    if(hr || !device) {snprintf(error_text,sizeof(error_text),"Cannot create USB device interface."); return 0;}
    rc=(*device)->USBDeviceOpen(device);
    if(rc) {snprintf(error_text,sizeof(error_text),"Cannot open mouse (0x%08x). Close other configuration apps and reconnect the mouse.",rc); (*device)->Release(device); device=NULL; return 0;}
    return 1;
}
static int begin(void) {
    // Mark before the first request so cleanup also runs after partial entry.
    session=1;
    return transfer(0x40,1,0,0,NULL,0) && out(0x5a09) && out(0x017f) && out(0x2009);
}
static int end(void) {
    int ok=1; char saved[256]; snprintf(saved,sizeof(saved),"%s",error_text);
    if(session) {
        if(!out(0x007f)) ok=0;
        if(!out(0x0009)) ok=0;
        if(!transfer(0x40,6,0,0,NULL,0)) ok=0;
        session=0;
    }
    if(saved[0]) snprintf(error_text,sizeof(error_text),"%s",saved);
    return ok;
}
static void close_mouse(void) {
    if(device) {(*device)->USBDeviceClose(device); (*device)->Release(device); device=NULL;}
}
static int number(const char *s,int lo,int hi,int *value) {
    char *tail; errno=0; long n=strtol(s,&tail,10);
    if(errno || !s[0] || *tail || n<lo || n>hi) return 0;
    *value=(int)n; return 1;
}
static int ratebyte(int hz) {
    switch(hz) {case 125:return 0xc2;case 250:return 0x82;case 500:return 0x42;case 1000:return 2;default:return -1;}
}
static int known_action(int n) {
    return n==224 || n==225 || n==229 || n==230 || n==231 || n==232 ||
           n==236 || n==237 || n==238 || n==239 || n==240 || n==242 || n==243;
}
static int readsettings(unsigned char *values,int *active) {
    if(!begin()) return 0;
    for(int i=1;i<=14;i++) if(!readreg(i,&values[i])) return 0;
    if(!out(0x007f)) return 0;
    unsigned char slot;
    if(!readreg(2,&slot)) return 0;
    *active=(slot&15)+1;
    if(*active>4) {snprintf(error_text,sizeof(error_text),"Mouse returned an unsupported active DPI slot (%u).",slot); return 0;}
    return end();
}
static void printsettings(unsigned char *v,int active) {
    int hz=0; switch(v[14]) {case 0xc2:hz=125;break;case 0x82:hz=250;break;case 0x42:hz=500;break;case 2:hz=1000;break;}
    printf("{\"vendor\":2362,\"product\":9523,\"activeSlot\":%d,\"speed\":%u,\"mode\":%u,\"action\":%u,\"rate\":%d,\"slots\":[",active,v[1],v[10]>>4,v[11],hz);
    for(int i=0;i<4;i++) printf("%s{\"dpi\":%d,\"color\":%d}",i?",":"",200+200*(v[i+2]&15),v[i+2]>>4);
    printf("],\"raw\":["); for(int i=1;i<=14;i++) printf("%s%u",i==1?"":",",v[i]); puts("]}");
}
int main(int argc,char **argv) {
    // All input is validated before opening or sending anything to the device.
    int apply=argc==16 && !strcmp(argv[1],"apply");
    int dpi[4],color[4],active=0,mode=0,speed=0,rate=0,action=0;
    if(apply) {
        int ok=1;
        for(int i=0;i<4;i++) ok &= number(argv[2+i*2],200,3200,&dpi[i]) && dpi[i]%200==0 && number(argv[3+i*2],0,15,&color[i]);
        ok &= number(argv[10],1,4,&active) && number(argv[11],0,14,&mode) && (mode==0||mode==2||mode==4||mode==6||mode==8||mode==10||mode==14);
        ok &= number(argv[12],0,255,&speed) && number(argv[13],125,1000,&rate) && ratebyte(rate)>=0;
        ok &= number(argv[14],0,255,&action) && known_action(action) && !strcmp(argv[15],"verified");
        if(!ok) {fprintf(stderr,"Invalid profile. No USB requests sent.\n");return 2;}
    } else if(argc!=2 || strcmp(argv[1],"read")) {
        fprintf(stderr,"Usage: vigilctl read | apply DPI1 COLOR1 DPI2 COLOR2 DPI3 COLOR3 DPI4 COLOR4 ACTIVE MODE SPEED RATE ACTION verified\n"); return 2;
    }
    if(!connect_mouse()) {fprintf(stderr,"%s\n",error_text); return 1;}
    unsigned char old[15]={0}; int oldactive=0; int ok=readsettings(old,&oldactive);
    if(ok && apply) {
        ok=begin();
        for(int i=0;ok && i<4;i++) {
            unsigned char next=(color[i]<<4)|(dpi[i]/200-1);
            if(next!=old[i+2]) ok=writereg(i+2,next);
        }
        if(ok && mode!=(old[10]>>4)) ok=writereg(10,(mode<<4)|(old[10]&15));
        if(ok && speed!=old[1]) ok=writereg(1,speed);
        if(ok && action!=old[11]) ok=writereg(11,action);
        if(ok && ratebyte(rate)!=old[14]) {usleep(60000);ok=writereg(14,ratebyte(rate));}
        if(ok && active!=oldactive) ok=writereg(9,(active-1)*0x20);
        if(!end()) ok=0;
        if(ok) {
            unsigned char actual[15]={0}; int actualactive=0; ok=readsettings(actual,&actualactive);
            if(ok) {
                for(int i=0;i<4;i++) if(actual[i+2]!=((color[i]<<4)|(dpi[i]/200-1))) ok=0;
                if(actual[1]!=speed || (actual[10]>>4)!=mode || actual[11]!=action || actual[14]!=ratebyte(rate) || actualactive!=active) ok=0;
                if(ok) printsettings(actual,actualactive);
                else snprintf(error_text,sizeof(error_text),"Settings were sent, but verification differs. Click Read mouse to inspect the current state.");
            }
        }
    } else if(ok) printsettings(old,oldactive);
    if(!end()) ok=0;
    close_mouse();
    if(!ok) {fprintf(stderr,"%s\n",error_text);return 1;} return 0;
}
