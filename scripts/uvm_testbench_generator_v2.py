import csv
import os
import sys

if len(sys.argv) < 2:
    print("Usage: python uvm_testbench_generator.py <protocol_name> [signals.csv]")
    sys.exit(1)

MODULE_NAME = sys.argv[1].lower()
CSV_FILE = sys.argv[2] if len(sys.argv) > 2 else "signals.csv"


def read_signals(csv_file):
    signals = []
    with open(csv_file, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) >= 3:
                signals.append({'name': row[0].strip(), 'dir': row[1].strip().lower(), 'width': int(row[2])})
    return signals


def generate_interface(signals):
    txt = f"interface {MODULE_NAME}_if;

"
    for sig in signals:
        if sig['width'] == 1:
            txt += f"  logic {sig['name']};
"
        else:
            txt += f"  logic [{sig['width']-1}:0] {sig['name']};
"
    txt += "
endinterface
"
    return txt


def main():
    signals = read_signals(CSV_FILE)
    outdir = f"{MODULE_NAME}_uvm"
    os.makedirs(outdir, exist_ok=True)

    with open(f"{outdir}/{MODULE_NAME}_if.sv", 'w') as f:
        f.write(generate_interface(signals))

    print(f"Generated files in {outdir}")


if __name__ == '__main__':
    main()
