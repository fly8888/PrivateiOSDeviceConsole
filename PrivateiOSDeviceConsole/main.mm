//
//  main.m
//  PrivateiOSDeviceConsole
//
//  Created by sunjianwen on 2017/3/29.
//  Copyright © 2017年 sunjianwen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "libimobiledevice.h"
#import "syslog_relay.h"

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

#ifdef WIN32
#include <windows.h>
#define sleep(x) Sleep(x*1000)
#endif

#define LogPath  ([NSHomeDirectory() stringByAppendingPathComponent:@"Desktop/Log.txt"])

static int quit_flag = 0;

void print_usage(int argc, char **argv);

static char * udid = NULL;

static idevice_t device = NULL;
static syslog_relay_client_t syslog = NULL;

static NSMutableString * processName = [[NSMutableString alloc]init];
static NSMutableString * mstr = [[NSMutableString alloc]init];

static BOOL pU = NO;
static BOOL pP = NO;
static BOOL pO = NO;

BOOL logGo = NO;

void writefile(NSString * string )
{
    
    NSString *filePath = LogPath;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if(![fileManager fileExistsAtPath:filePath])
    {
        NSString *str = @"start";
        [str writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
    }
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:filePath];
    
    [fileHandle seekToEndOfFile];
    
    NSData* stringData  = [string dataUsingEncoding:NSUTF8StringEncoding];
    
    [fileHandle writeData:stringData]; //追加写入数据
    
    [fileHandle closeFile];
}


static void syslog_callback(char c, void *user_data)
{
    
    [mstr appendFormat:@"%c",c];
    if (c == '\n') {
        
        
        if([[mstr lowercaseString] rangeOfString:@"["].location!=NSNotFound&&
           [[mstr lowercaseString] rangeOfString:@"]"].location!=NSNotFound&&
           [[mstr lowercaseString] rangeOfString:@"<"].location!=NSNotFound&&
           [[mstr lowercaseString] rangeOfString:@">"].location!=NSNotFound)
        {
            logGo = NO;
            
        }
        if(processName.length>0)
        {
            if([[mstr lowercaseString] rangeOfString:[processName lowercaseString]].location!=NSNotFound)
            {
                logGo = YES;
            }
            
        }else
        {
            logGo = YES;
        }
        
        
        if(logGo)
        {
            printf("%s",[mstr UTF8String]);
            fflush(stdout);
            if(pO)
            {
                writefile(mstr);
            }
           
        }

        [mstr setString:@""];
    }
}

static int start_logging(void)
{
    idevice_error_t ret = idevice_new(&device, udid);
    if (ret != IDEVICE_E_SUCCESS) {
        fprintf(stderr, "Device with udid %s not found!?\n", udid);
        return -1;
    }
    
    /* start and connect to syslog_relay service */
    syslog_relay_error_t serr = SYSLOG_RELAY_E_UNKNOWN_ERROR;
    serr = syslog_relay_client_start_service(device, &syslog, "idevicesyslog");
    if (serr != SYSLOG_RELAY_E_SUCCESS) {
        fprintf(stderr, "ERROR: Could not start service com.apple.syslog_relay.\n");
        idevice_free(device);
        device = NULL;
        return -1;
    }
    
    /* start capturing syslog */
    serr = syslog_relay_start_capture(syslog, syslog_callback, NULL);
    if (serr != SYSLOG_RELAY_E_SUCCESS) {
        fprintf(stderr, "ERROR: Unable tot start capturing syslog.\n");
        syslog_relay_client_free(syslog);
        syslog = NULL;
        idevice_free(device);
        device = NULL;
        return -1;
    }
    
    fprintf(stdout, "[connected]\n");
    
    fflush(stdout);
    
    return 0;
}

static void stop_logging(void)
{
    fflush(stdout);
    
    if (syslog) {
        syslog_relay_client_free(syslog);
        syslog = NULL;
    }
    
    if (device) {
        idevice_free(device);
        device = NULL;
    }
}

static void device_event_cb(const idevice_event_t* event, void* userdata)
{
    if (event->event == IDEVICE_DEVICE_ADD) {
        if (!syslog) {
            if (!udid) {
                udid = strdup(event->udid);
            }
            if (strcmp(udid, event->udid) == 0) {
                if (start_logging() != 0) {
                    fprintf(stderr, "Could not start logger for udid %s\n", udid);
                }
            }
        }
    } else if (event->event == IDEVICE_DEVICE_REMOVE) {
        if (syslog && (strcmp(udid, event->udid) == 0)) {
            stop_logging();
            fprintf(stdout, "[disconnected]\n");
        }
    }
}

/**
 * signal handler function for cleaning up properly
 */
static void clean_exit(int sig)
{
    fprintf(stderr, "\nExiting...\n");
    quit_flag++;
}

static void startlog()
{
    int num = 0;
    char **devices = NULL;
    idevice_get_device_list(&devices, &num);
    idevice_device_list_free(devices);
    if (num == 0) {
        if (!udid) {
            fprintf(stderr, "No device found. Plug in a device or pass UDID with -u to wait for device to be available.\n");
            
        } else {
            fprintf(stderr, "Waiting for device with UDID %s to become available...\n", udid);
        }
    }
    
    idevice_event_subscribe(device_event_cb, NULL);
    

}


int main(int argc, char *argv[])
{
  
    
    signal(SIGINT, clean_exit);
    signal(SIGTERM, clean_exit);
#ifndef WIN32
    signal(SIGQUIT, clean_exit);
    signal(SIGPIPE, SIG_IGN);
#endif
    
    NSLog(@"%@",NSHomeDirectory());
    if(argc == 1)
    {
        print_usage(argc, argv);
        return 0;
    }
    
    NSArray * arguments = [[NSProcessInfo processInfo]arguments];
   
    
    
    for (int j =1 ; j<arguments.count; j++) {
        
        idevice_set_debug_level(1);
        
        NSString * op1 = arguments[j];
        if([[op1 lowercaseString] isEqualToString:@"-u"])
        {
            j++;
            if(j < arguments.count)
            {
                NSString * op2 = arguments[j];
                if(op2.length == 40)
                {
                    pU = YES;
                    udid =(char *)[op2 UTF8String];
                    continue;
                }
            }
        }
        if([[op1 lowercaseString] isEqualToString:@"-p"])
        {
            j++;
            if(j < arguments.count)
            {
                NSString * op2 = arguments[j];
                if(op2.length > 0)
                {
                    pP =YES;
                    [processName setString:op2];
                }
            }
        }
        if([[op1 lowercaseString] isEqualToString:@"-o"])
        {
            pO = YES;
        }
        
    }
    
    if(pU&&pP)
    {
        startlog();
        
        while (!quit_flag) {
            sleep(1);
        }
        
        idevice_event_unsubscribe();
        stop_logging();
        
    }
    
    
    if (udid) {
        free(udid);
    }
        
    return 0;
}

void print_usage(int argc, char **argv)
{
    char *name = NULL;
    
    name = strrchr(argv[0], '/');
    printf("Usage: %s [OPTIONS]\n", (name ? name + 1: argv[0]));
    printf("Relay syslog of a connected device.\n\n");
    printf("  -d, --debug\t\tenable communication debugging\n");
    printf("  -u, --udid UDID\ttarget specific device by its 40-digit device UDID\n");
    printf("  -h, --help\t\tprints usage information\n");
    printf("  -u , -p --uuid And Process");
    printf("\n");
    //    printf("Homepage: <" PACKAGE_URL ">\n");
}
