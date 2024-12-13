def read_data_file(filename):
    data_bytes = {}
    current_address = None

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            if line.startswith('@'):
                # New address marker
                current_address = int(line[2:], 16)
            else:
                # Read byte values
                bytes_list = line.split()
                for byte in bytes_list:
                    data_bytes[current_address] = int(byte, 16)
                    current_address += 1

    return data_bytes

def parse_log(log_str):
    log_entries = []
    for line in log_str.strip().split('\n'):
        if '->' not in line:
            continue
        addr_str, value_str = line.split('->')
        addr = int(addr_str.strip(), 16)
        value = int(value_str.strip(), 16)
        log_entries.append((addr, value))
    return log_entries

def check_consistency(data_bytes, log_entries):
    wrong_lines = []

    for i, (addr, log_value) in enumerate(log_entries, 1):
        # Extract bytes from the log value (32-bit value)
        log_bytes = [
            (log_value >> 24) & 0xFF,
            (log_value >> 16) & 0xFF,
            (log_value >> 8) & 0xFF,
            log_value & 0xFF
        ]

        # Check each byte
        for offset in range(4):
            data_addr = addr + offset
            if data_addr in data_bytes:
                expected_byte = data_bytes[data_addr]
                actual_byte = log_bytes[3-offset]  # Reverse order due to endianness
                if expected_byte != actual_byte:
                    wrong_lines.append(i)
                    # print(i, log_bytes, data_bytes[addr], data_bytes[addr+1], data_bytes[addr+2], data_bytes[addr+3])
                    # print in hex
                    print(i, hex(addr), hex(log_bytes[3]), hex(log_bytes[2]), hex(log_bytes[1]), hex(log_bytes[0]), "|", hex(data_bytes[addr]), hex(data_bytes[addr+1]), hex(data_bytes[addr+2]), hex(data_bytes[addr+3]))
                    break

    return wrong_lines

# Example usage
data_file = "/home/zj/Projects/ACM-CPU/testcase/sim/000_array_test1.data"
log_file = """out.log"""
log_file = """/home/zj/Projects/CPU_Project/CPU_Project.sim/sim_1/behav/xsim/out.log"""

with open(log_file, 'r') as f:
    log_str = f.read()

# Read the data file
data_bytes = read_data_file(data_file)

# Parse the log
log_entries = parse_log(log_str)

print("Number of log entries:", len(log_entries))

# Check consistency and print wrong lines
wrong_lines = check_consistency(data_bytes, log_entries)
if wrong_lines:
    print("Inconsistent lines (line numbers):", wrong_lines)
else:
    print("All log entries are consistent with the data file")