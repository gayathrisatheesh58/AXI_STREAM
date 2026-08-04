/******************************************************************************
 * Project : AXI Stream Loopback Test
 * Board   : Zybo Z7-10
 * Device  : Zynq-7000
 * Tool    : Vitis Unified IDE 2025.2
 *
 * Description:
 *  This application tests an AXI4-Stream loopback IP using AXI DMA
 *  operating in Simple Mode (Direct Register Mode).
 *
 * Data Flow:
 *
 *  DDR Memory
 *      |
 *      |  (MM2S)
 *      V
 *  AXI DMA  ------------>
 *                    AXI4-Stream
 *                         |
 *                  axis_loopback IP
 *                         |
 *                    AXI4-Stream
 *  AXI DMA  <------------
 *      ^
 *      |  (S2MM)
 *      |
 *  DDR Memory
 *
 * Finally the received data is compared against the transmitted data.
 ******************************************************************************/

#include <stdio.h>
#include <string.h>

#include "xparameters.h"
#include "xaxidma.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xstatus.h"

/*--------------------------------------------------------------------
 * DMA Hardware Definitions
 *-------------------------------------------------------------------*/

#define DMA_BASEADDR    XPAR_AXI_DMA_0_BASEADDR

/*--------------------------------------------------------------------
 * DDR Memory Locations
 *-------------------------------------------------------------------*/

#define DDR_BASE_ADDR   XPAR_PS7_DDR_0_BASEADDRESS

#define MEM_BASE_ADDR   (DDR_BASE_ADDR + 0x01000000)

#define TX_BUFFER_BASE  (MEM_BASE_ADDR + 0x00100000)

#define RX_BUFFER_BASE  (MEM_BASE_ADDR + 0x00300000)

/*--------------------------------------------------------------------
 * Packet Configuration
 *-------------------------------------------------------------------*/

#define MAX_PKT_LEN     1024

#define POLL_TIMEOUT    1000000

/*--------------------------------------------------------------------
 * Global Variables
 *-------------------------------------------------------------------*/

XAxiDma AxiDma;

/*--------------------------------------------------------------------
 * Function Prototypes
 *-------------------------------------------------------------------*/

static int InitDma(void);

static void FillTxBuffer(u8 *TxBuf, u32 Length);

static int CheckData(u8 *TxBuf,
                     u8 *RxBuf,
                     u32 Length);

static int PollTransferDone(XAxiDma *DmaInst,
                            int Direction);

/*--------------------------------------------------------------------
 * Main Program
 *-------------------------------------------------------------------*/

int main(void)
{
    int Status;

    u8 *TxBufferPtr = (u8 *)TX_BUFFER_BASE;
    u8 *RxBufferPtr = (u8 *)RX_BUFFER_BASE;

    xil_printf("\r\n");
    xil_printf("=========================================\r\n");
    xil_printf("      AXI DMA LOOPBACK TEST STARTED      \r\n");
    xil_printf("=========================================\r\n");

    /**********************************************************
     * Step 1 : Initialize AXI DMA
     **********************************************************/

    Status = InitDma();

    if (Status != XST_SUCCESS)
    {
        xil_printf("ERROR : DMA Initialization Failed\r\n");
        return XST_FAILURE;
    }

    xil_printf("DMA Initialized Successfully\r\n");

    /**********************************************************
     * Step 2 : Prepare Buffers
     **********************************************************/

    FillTxBuffer(TxBufferPtr, MAX_PKT_LEN);

    memset(RxBufferPtr, 0, MAX_PKT_LEN);

    Xil_DCacheFlushRange((UINTPTR)TxBufferPtr,
                         MAX_PKT_LEN);

    Xil_DCacheInvalidateRange((UINTPTR)RxBufferPtr,
                              MAX_PKT_LEN);

    xil_printf("Buffers Prepared\r\n");

    /**********************************************************
     * Step 3 : Start Receive DMA First (S2MM)
     **********************************************************/

    Status = XAxiDma_SimpleTransfer(
                    &AxiDma,
                    (UINTPTR)RxBufferPtr,
                    MAX_PKT_LEN,
                    XAXIDMA_DEVICE_TO_DMA);

    if (Status != XST_SUCCESS)
    {
        xil_printf("ERROR : RX Transfer Submission Failed\r\n");
        return XST_FAILURE;
    }

    /**********************************************************
     * Step 4 : Start Transmit DMA (MM2S)
     **********************************************************/

    Status = XAxiDma_SimpleTransfer(
                    &AxiDma,
                    (UINTPTR)TxBufferPtr,
                    MAX_PKT_LEN,
                    XAXIDMA_DMA_TO_DEVICE);

    if (Status != XST_SUCCESS)
    {
        xil_printf("ERROR : TX Transfer Submission Failed\r\n");
        return XST_FAILURE;
    }

    /**********************************************************
     * Step 5 : Wait Until Both Transfers Finish
     **********************************************************/

    if (PollTransferDone(&AxiDma,
                         XAXIDMA_DMA_TO_DEVICE)
            != XST_SUCCESS)
    {
        xil_printf("ERROR : TX Timeout\r\n");
        return XST_FAILURE;
    }

    if (PollTransferDone(&AxiDma,
                         XAXIDMA_DEVICE_TO_DMA)
            != XST_SUCCESS)
    {
        xil_printf("ERROR : RX Timeout\r\n");
        return XST_FAILURE;
    }

    /**********************************************************
     * Step 6 : Refresh RX Cache
     **********************************************************/

    Xil_DCacheInvalidateRange((UINTPTR)RxBufferPtr,
                              MAX_PKT_LEN);

    /**********************************************************
     * Step 7 : Compare Data
     **********************************************************/

    Status = CheckData(TxBufferPtr,
                       RxBufferPtr,
                       MAX_PKT_LEN);

    if (Status == XST_SUCCESS)
    {
        xil_printf("\r\n");
        xil_printf("*********************************\r\n");
        xil_printf("********** TEST PASSED **********\r\n");
        xil_printf("*********************************\r\n");
    }
    else
    {
        xil_printf("\r\n");
        xil_printf("*********************************\r\n");
        xil_printf("********** TEST FAILED **********\r\n");
        xil_printf("*********************************\r\n");
    }

    while (1);

    return XST_SUCCESS;
}

/******************************************************************************
 * Function : InitDma()
 *
 * Description:
 *      Initializes the AXI DMA engine in Simple Mode.
 ******************************************************************************/

static int InitDma(void)
{
    XAxiDma_Config *CfgPtr;

    int Timeout;

    /**********************************************************
     * Lookup DMA Configuration
     **********************************************************/

    CfgPtr = XAxiDma_LookupConfigBaseAddr(DMA_BASEADDR);

    if (CfgPtr == NULL)
    {
        xil_printf("ERROR : DMA Configuration Not Found\r\n");
        return XST_FAILURE;
    }

    /**********************************************************
     * Initialize DMA Driver
     **********************************************************/

    if (XAxiDma_CfgInitialize(&AxiDma,
                              CfgPtr) != XST_SUCCESS)
    {
        xil_printf("ERROR : DMA Driver Initialization Failed\r\n");
        return XST_FAILURE;
    }

    /**********************************************************
     * Verify Simple DMA Mode
     **********************************************************/

    if (XAxiDma_HasSg(&AxiDma))
    {
        xil_printf("ERROR : Scatter-Gather Mode Detected\r\n");
        xil_printf("Configure AXI DMA for Simple Mode\r\n");
        return XST_FAILURE;
    }

    /**********************************************************
     * Reset DMA
     **********************************************************/

    XAxiDma_Reset(&AxiDma);

    Timeout = POLL_TIMEOUT;

    while ((!XAxiDma_ResetIsDone(&AxiDma)) &&
           (Timeout > 0))
    {
        Timeout--;
    }

    if (Timeout == 0)
    {
        xil_printf("ERROR : DMA Reset Timeout\r\n");
        return XST_FAILURE;
    }

    xil_printf("DMA Ready\r\n");

    return XST_SUCCESS;
}
/******************************************************************************
 * Function : FillTxBuffer()
 *
 * Description:
 *      Fills the transmit buffer with a known test pattern.
 *      The receiver should receive exactly the same bytes.
 ******************************************************************************/

static void FillTxBuffer(u8 *TxBuf, u32 Length)
{
    u32 Index;

    for (Index = 0; Index < Length; Index++)
    {
        TxBuf[Index] = (u8)(Index & 0xFF);
    }

    xil_printf("TX Buffer Filled (%lu Bytes)\r\n",
               (unsigned long)Length);
}
/******************************************************************************
 * Function : CheckData()
 *
 * Description:
 *      Compares the transmitted and received buffers byte-by-byte.
 *      Returns PASS if every byte matches.
 ******************************************************************************/

static int CheckData(u8 *TxBuf,
                     u8 *RxBuf,
                     u32 Length)
{
    u32 Index;

    for (Index = 0; Index < Length; Index++)
    {
        if (TxBuf[Index] != RxBuf[Index])
        {
            xil_printf("\r\n");
            xil_printf("DATA MISMATCH DETECTED\r\n");
            xil_printf("----------------------\r\n");
            xil_printf("Byte Number : %lu\r\n",
                       (unsigned long)Index);
            xil_printf("Expected    : 0x%02X\r\n",
                       TxBuf[Index]);
            xil_printf("Received    : 0x%02X\r\n",
                       RxBuf[Index]);

            return XST_FAILURE;
        }
    }

    xil_printf("Data Verification Successful\r\n");

    return XST_SUCCESS;
}
/******************************************************************************
 * Function : PollTransferDone()
 *
 * Description:
 *      Waits until the selected DMA channel finishes transferring data.
 *
 * Parameters:
 *      DmaInst   : Pointer to AXI DMA instance
 *      Direction :
 *          XAXIDMA_DMA_TO_DEVICE  -> MM2S (TX)
 *          XAXIDMA_DEVICE_TO_DMA  -> S2MM (RX)
 *
 * Returns:
 *      XST_SUCCESS  - Transfer completed
 *      XST_FAILURE  - Timeout occurred
 ******************************************************************************/

static int PollTransferDone(XAxiDma *DmaInst,
                            int Direction)
{
    int Timeout = POLL_TIMEOUT;

    while (XAxiDma_Busy(DmaInst, Direction) &&
           (Timeout > 0))
    {
        Timeout--;
    }

    if (Timeout == 0)
    {
        xil_printf("DMA Transfer Timeout\r\n");
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}
