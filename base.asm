IDEAL
MODEL small
STACK 100h

; status byte values
STATUS_EMPTY     EQU 0
STATUS_OCCUPIED  EQU 1
STATUS_DELETED EQU 2

; capacity and buffer sizes
TABLE_CAPACITY   EQU 64
KEY_MAX_LEN      EQU 15       ;+ 1 zero terminator
KEY_BUF_SIZE     EQU 16
VAL_MAX_LEN      EQU 31       ;+ 1 zero terminator
VAL_BUF_SIZE     EQU 32

; entry size & offsets
ENTRY_STATUS     EQU 0
ENTRY_KEY        EQU 1        
ENTRY_VALUE      EQU 17       
ENTRY_SIZE       EQU 49       ; 1 + 16 + 32 = 49

 

TABLE_TOTAL_SIZE EQU TABLE_CAPACITY * ENTRY_SIZE  ; 3136 bytes total

DATASEG
    myTable db TABLE_TOTAL_SIZE dup(STATUS_EMPTY)
    keyInputMax db KEY_BUF_SIZE
    keyInputLen db ?
    keyInputBuffer db KEY_BUF_SIZE dup(?)
    valueStringBuffer db VAL_BUF_SIZE dup(?)
   
    testKey1    db 'admin', 0
    testVal1    db 'secret_123', 0

    testKey2    db 'guest', 0
    testVal2    db 'read_only', 0
    updatedVal      db 'NEW_PASSWORD', 0

    colonSep   db ': $', 0
    arrowSep   db ' => $', 0
    crlf       db 13, 10, '$'   
    
    deletekey db 'admin', 0

    occupiedMsg db 'Occupied slots: $', 0
    deletedMsg  db 'Deleted slots:  $', 0

CODESEG
start:
    mov ax, @data
    mov ds, ax
    mov bl, 2
  
    call Init

  
   
    lea si, [testKey1]
    lea di, [keyInputBuffer]
    call CopyString

    
    lea si, [testVal1]
    lea di, [valueStringBuffer]
    call CopyString

   
    lea di, [keyInputBuffer]
    call HashKey
    call InsertEntry
    
    lea si, [testKey2]
    lea di, [keyInputBuffer]
    call CopyString

    lea si, [testVal2]
    lea di, [valueStringBuffer]
    call CopyString

    lea di, [keyInputBuffer]
    call HashKey                
    call InsertEntry
  
    lea si, [testKey1]
    lea di, [keyInputBuffer]
    call CopyString

    lea si, [updatedVal]
    lea di, [valueStringBuffer]
    call CopyString


    lea di, [keyInputBuffer]
    call HashKey                 

    
    call InsertEntry
    
    
    
    call PrintTable
    
    lea si, [deletekey]
    call DeleteByKey
    
   
    call GetTableStats

   
    call PrintTableStats
    jmp exit

     
proc Init ; initiallize table bytes
    lea di, [myTable]
    mov cx, TABLE_TOTAL_SIZE
    
InitLoop: 
    mov [byte ptr di], STATUS_EMPTY
    inc di
    loop InitLoop
    ret
    
endp Init

proc GetSlotAddress ; slot input goes through bl reg, changes di to point to slot
    push ax
    lea di, [myTable]
    mov al, ENTRY_SIZE
    mul bl
    add di, ax
    pop ax
    ret
endp GetSlotAddress

proc HashKey ; turns string (null terminated, given pointer di) into a slot index, store res in bl
    push ax
    push cx
    push dx
    push di
    push bx
    
    xor ax, ax ; hash accumulator
    mov bx, 31
    
HashKeyLoop:
    mov cl, [byte ptr di]
    cmp cl, 0
    je HashEnd
    mul bx
    xor ch, ch ; cx to contain char
    add ax, cx
    inc di
    jmp HashKeyLoop
HashEnd:
    and ax, 003Fh ; %64
    mov bl, al
    pop bx
    pop di
    pop dx
    pop cx   
    pop ax
    ret
endp HashKey

proc CompareKeys ; si reg points to input key, di reg points to (slot + 1) ; output: zf = 0 dif, zf =1 iden
    push ax
    push si
    push di
    
CompareLoop:
    mov ax, [si]
    cmp ax, [di]
    jne Done
    cmp al, 0
    je Done
    add si, 2
    add di, 2
    jmp CompareLoop
    
Done:
    pop di
    pop si
    pop ax
    ret
endp CompareKeys


proc InsertEntry ; 
    push ax
    push bx
    push cx
    push di
    
    
    mov cx, 64
    
CheckForPlace:        
    call GetSlotAddress ;bl - slot, di - pointer
    cmp [byte ptr di], STATUS_EMPTY
    je FreeSlot
    cmp [byte ptr di], STATUS_DELETED
    je FreeSlot
    ; occupied
    lea si, [keyInputBuffer]
    lea di, [di + ENTRY_KEY]
    call CompareKeys
    jz KeyExists
    jnz KeySame
KeyExists:
    call GetSlotAddress ; to check the key i shifted the di reg, calling the function resets it to add the ENTRY_VALUE
    lea si, [valueStringBuffer]
    lea di, [byte ptr di + ENTRY_VALUE]
    call CopyString
    jmp DoneInsert
    
KeySame:
    inc bl
    and bl, 003Fh
    call GetSlotAddress
    loop CheckForPlace
    jmp DoneInsert
    
FreeSlot:
    call GetSlotAddress
    mov [byte ptr di], STATUS_OCCUPIED
    lea si, [keyInputBuffer]
    lea di, [byte ptr di + ENTRY_KEY]
    call CopyString 
    call GetSlotAddress
    lea si, [valueStringBuffer]
    lea di, [byte ptr di + ENTRY_VALUE]
    call CopyString   
DoneInsert:  
    pop di
    pop cx
    pop bx
    pop ax
    ret
endp InsertEntry

proc CopyString ; input: si to org string, di to dest
    push ax
    push si
    push di

StringLoop:
    mov al, [byte ptr si]
    mov [byte ptr di], al
    cmp al, 0
    je CopyStringDone
    inc si
    inc di
    jmp StringLoop

CopyStringDone:
    pop di
    pop si
    pop ax
    ret
endp CopyString

proc FindEntry ; si points to key, output: cf = 0 found -> di points to slot val, cf = 1 doesnt exist
    push si
    push ax
    push cx
    
    mov cx, 64
    mov ax, si
    mov di, ax
    call HashKey
FindEntryLoop:   
   
    call GetSlotAddress
    cmp [byte ptr di], STATUS_EMPTY
    je DoneFindEntry_1    
    cmp [byte ptr di], STATUS_DELETED
    je DeletedEntry
    jmp OccupiedEntry
    
DoneFindEntry_1:
    STC
    jmp DoneFindEntry
    
DeletedEntry:
    inc bl
    and bl, 003Fh
    loop FindEntryLoop
    jmp DoneFindEntry_1
    
OccupiedEntry: 
    push di
    lea di, [di + 1]
    call CompareKeys
    pop di 
    jz DoneFindEntry_2 
    jmp DeletedEntry
    
DoneFindEntry_2:
    CLC
    lea di, [di + ENTRY_VALUE]
    
DoneFindEntry:    
    pop cx
    pop ax
    pop si    
    ret
endp FindEntry
    
proc PrintTable
    push di
    push cx
    push bx
    
    lea di, [myTable]
    mov cx, 64
    mov bl, 0
  
     
PrintTableLoop:       
    cmp [byte ptr di], STATUS_OCCUPIED
    jne Skip
    call PrintSlot
    
Skip:
    add di, 49
    inc bl
    loop PrintTableLoop
    
    pop bx
    pop cx
    pop di
    ret
endp PrintTable
    
proc PrintSlot ; slot index: key => value
    push ax
    push dx
    push si
    
    mov al, bl
    call PrintDec
    
    lea dx, [colonSep]
    mov ah, 9h
    int 21h
    
    lea si, [di + ENTRY_KEY]
    call PrintNullString
   
    lea dx, [arrowSep]
    mov ah, 09h
    int 21h

    
    lea si, [di + ENTRY_VALUE]
    call PrintNullString
    
    lea dx, [crlf]
    mov ah, 9h
    int 21h
    
    pop si
    pop dx
    pop ax
    
    ret
endp PrintSlot  

proc PrintNullString ; si points to string
    push ax
    push dx
    push si

PrintNullLoop:
    mov dl, [byte ptr si]
    cmp dl, 0
    je PrintNullDone
    mov ah, 02h               
    int 21h
    inc si
    jmp PrintNullLoop

PrintNullDone:
    pop si
    pop dx
    pop ax
    ret
endp PrintNullString


proc PrintDec ; al points to num
    push ax
    push dx

    aam                      
    push ax                   

    mov dl, ah
    add dl, '0'             
    mov ah, 02h
    int 21h

    pop ax
    mov dl, al
    add dl, '0'             
    mov ah, 02h
    int 21h

    pop dx
    pop ax
    ret
endp PrintDec

proc DeleteEntry ; get slot index in bl reg, output: cf = 1 not found, cf = 0 success
    push bx
    push ax
    push di

    cmp bl, 64
    jae FailDelete
    call GetSlotAddress
    cmp [byte ptr di], STATUS_EMPTY
    je FailDelete
    cmp [byte ptr di], STATUS_OCCUPIED
    je Occupied
    cmp [byte ptr di], STATUS_DELETED
    je FailDelete
    
FailDelete:
    STC
    jmp DoneDelete
    
Occupied:
     mov [di], STATUS_DELETED
     mov ax, di ; keep address to slot start
     
    ; clean key buffer
     mov bl, KEY_BUF_SIZE 
     lea di, [di + ENTRY_KEY]
     call ClearBuffer
     
     ; reset di
     mov di, ax
     
     ; clean value buffer
     mov bl, VAL_BUF_SIZE 
     lea di, [di + ENTRY_VALUE]
     call ClearBuffer
     CLC
     
DoneDelete:
     pop di
     pop ax
     pop bx
     ret
      
endp DeleteEntry  
    
proc ClearBuffer ; di points to string, bl = how many to clear
    push ax
    push bx
    push di
    
    xor ax, ax
ClearLoop:
    cmp bl, 0
    je DoneClear
    dec bl
    mov [byte ptr di], al
    inc di
    jmp ClearLoop
    
DoneClear:
    pop di
    pop bx
    pop ax
    ret
endp ClearBuffer
    
proc DeleteByKey ; di to null-terminated string, cf = 0 success, cf = 1 fail
    push di
    push bx    
    push cx
    push si 
    
    mov cx, 64
    mov si, di
    call HashKey 
DeleteLoop:
    call GetSlotAddress
    
    cmp [byte ptr di], STATUS_EMPTY
    je ErrorDelete
    
    cmp [byte ptr di], STATUS_DELETED
    je CheckDK

    push di
    lea di, [di + 1]
    call CompareKeys
    pop di
    jnz CheckDK
    call DeleteEntry
    CLC
    jmp DoneDK
CheckDK:
    inc bl
    and bl, 003Fh
    loop DeleteLoop
ErrorDelete:
    STC 
    
DoneDK:
    pop si
    pop cx
    pop bx
    pop di
    ret
endp DeleteByKey

proc GetTableStats ; al -occupied count, ah - deleted count
    push cx
    push di

    
    xor ax, ax
 
    mov cx, 64
    lea di, [myTable]
    
TableStatsLoop:
    cmp [byte ptr di], STATUS_OCCUPIED
    je OccupiedCount
    cmp [byte ptr di], STATUS_DELETED
    je DeletedCount
    jmp ContStats
OccupiedCount:
    inc al
    jmp ContStats
DeletedCount:
    inc ah
    
ContStats:
    add di, ENTRY_SIZE
    loop TableStatsLoop
    
  
    pop di
    pop cx
    ret
endp GetTableStats

proc PrintTableStats
    push ax
    push dx

    push ax                   

    lea dx, [occupiedMsg]
    mov ah, 09h
    int 21h

    call PrintDec

    lea dx, [crlf]
    mov ah, 09h
    int 21h

    lea dx, [deletedMsg]
    mov ah, 09h
    int 21h

    pop ax                    
    mov al, ah               
    call PrintDec

    lea dx, [crlf]
    mov ah, 09h
    int 21h

    pop dx
    pop ax
    ret
endp PrintTableStats

exit:
    mov ax, 4c00h
    int 21h
END start