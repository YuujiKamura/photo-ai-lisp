package main

import (
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"time"
)

func main() {
	// (1) whoami
	fmt.Println("--- START Case (1): whoami ---")
	runCase("whoami\r\n", 2*time.Second)
	fmt.Println("--- END Case (1) ---")

	// (2) echo hello
	fmt.Println("--- START Case (2): echo hello ---")
	runCase("echo hello\r\nexit\r\n", 0) 
	fmt.Println("--- END Case (2) ---")

	// (3) pick-agent
	fmt.Println("--- START Case (3): pick-agent ---")
	runCase3()
	fmt.Println("--- END Case (3) ---")
}

func runCase(input string, delay time.Duration) {
	startTime := time.Now()
	cmd := exec.Command("tools/conpty-bridge/conpty-bridge.exe")
	stdin, _ := cmd.StdinPipe()
	stdout, _ := cmd.StdoutPipe()
	
	if err := cmd.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "Start failed: %v\n", err)
		return
	}
	
	done := make(chan bool)
	go func() {
		buf := make([]byte, 1024)
		for {
			n, err := stdout.Read(buf)
			if n > 0 {
				elapsed := time.Since(startTime).Milliseconds()
				fmt.Printf("[T+%03dms] %s\n", elapsed, hex.EncodeToString(buf[:n]))
			}
			if err != nil {
				break
			}
		}
		done <- true
	}()
	
	fmt.Fprint(stdin, input)
	
	if delay > 0 {
		time.Sleep(delay)
		fmt.Fprint(stdin, "exit\r\n")
		
		// Safety timeout
		timer := time.AfterFunc(2*time.Second, func() {
			cmd.Process.Kill()
		})
		cmd.Wait()
		timer.Stop()
	} else {
		// Wait with safety timeout
		timer := time.AfterFunc(5*time.Second, func() {
			cmd.Process.Kill()
		})
		cmd.Wait()
		timer.Stop()
	}
	<-done
}

func runCase3() {
	startTime := time.Now()
	cmd := exec.Command("tools/conpty-bridge/conpty-bridge.exe")
	stdin, _ := cmd.StdinPipe()
	stdout, _ := cmd.StdoutPipe()
	
	if err := cmd.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "Start failed: %v\n", err)
		return
	}
	
	done := make(chan bool)
	go func() {
		buf := make([]byte, 1024)
		for {
			n, err := stdout.Read(buf)
			if n > 0 {
				elapsed := time.Since(startTime).Milliseconds()
				fmt.Printf("[T+%03dms] %s\n", elapsed, hex.EncodeToString(buf[:n]))
			}
			if err != nil {
				break
			}
		}
		done <- true
	}()
	
	// Write "scripts\pick-agent.cmd\r\n"
	fmt.Fprint(stdin, "scripts\\pick-agent.cmd\r\n")
	time.Sleep(1 * time.Second)
	
	// Write "1\r\n"
	fmt.Fprint(stdin, "1\r\n")
	time.Sleep(3 * time.Second)
	
	fmt.Fprint(stdin, "exit\r\n")
	timer := time.AfterFunc(2*time.Second, func() {
		cmd.Process.Kill()
	})
	cmd.Wait()
	timer.Stop()
	<-done
}
