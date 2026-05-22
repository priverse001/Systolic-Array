import numpy as np
import os
import argparse


def to_twos_complement_hex(value, bit_width):
    """Convert a signed integer to its two's complement hex string."""
    value = int(value)  # Convert from numpy int to Python int
    if value < 0:
        value = (1 << bit_width) + value
    hex_digits = (bit_width + 3) // 4  # ceiling division
    return f"{value:0{hex_digits}x}"


def generate_test_vectors(rows, cols, k_dim, data_width, out_dir):
    """
    Generates test vectors for a systolic array MatMul: C = A @ B
    
    A: Input activation matrix of shape (rows, k_dim)
    B: Weight matrix of shape (k_dim, cols)
    C: Output matrix of shape (rows, cols)
    
    All values are random signed integers within the data_width range.
    Output files are hex-formatted for Verilog $readmemh.
    """
    print(f"Generating test vectors: A[{rows}x{k_dim}] @ B[{k_dim}x{cols}] = C[{rows}x{cols}]")
    print(f"Data width: {data_width} bits (signed range: [{-(1<<(data_width-1))}, {(1<<(data_width-1))-1}])")
    
    max_val = (1 << (data_width - 1)) - 1
    min_val = -(1 << (data_width - 1))
    acc_width = 32
    
    # Generate random signed integer matrices
    A = np.random.randint(min_val, max_val + 1, size=(rows, k_dim), dtype=np.int32)
    B = np.random.randint(min_val, max_val + 1, size=(k_dim, cols), dtype=np.int32)
    
    # Compute golden reference: use int64 to prevent overflow during matmul
    C = np.matmul(A.astype(np.int64), B.astype(np.int64))
    
    os.makedirs(out_dir, exist_ok=True)
    
    # Write A: row-major order (A[0][0], A[0][1], ..., A[1][0], ...)
    with open(os.path.join(out_dir, "matrix_a.hex"), "w") as f:
        for i in range(rows):
            for j in range(k_dim):
                f.write(to_twos_complement_hex(A[i, j], data_width) + "\n")
    
    # Write B: row-major order (B[0][0], B[0][1], ..., B[1][0], ...)
    with open(os.path.join(out_dir, "matrix_b.hex"), "w") as f:
        for i in range(k_dim):
            for j in range(cols):
                f.write(to_twos_complement_hex(B[i, j], data_width) + "\n")
    
    # Write C (expected): row-major order, using accumulator width
    with open(os.path.join(out_dir, "matrix_c_expected.hex"), "w") as f:
        for i in range(rows):
            for j in range(cols):
                f.write(to_twos_complement_hex(C[i, j], acc_width) + "\n")
    
    print(f"\nFiles saved to: {os.path.abspath(out_dir)}")
    print(f"  matrix_a.hex         ({rows*k_dim} values)")
    print(f"  matrix_b.hex         ({k_dim*cols} values)")
    print(f"  matrix_c_expected.hex ({rows*cols} values)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate systolic array test vectors")
    parser.add_argument("--rows", type=int, default=128, help="Number of rows (default: 128)")
    parser.add_argument("--cols", type=int, default=128, help="Number of columns (default: 128)")
    parser.add_argument("--k_dim", type=int, default=128, help="Inner dimension K (default: 128)")
    parser.add_argument("--data_width", type=int, default=8, help="Data width in bits (default: 8)")
    parser.add_argument("--out_dir", type=str, default="../data", help="Output directory")
    parser.add_argument("--seed", type=int, default=None, help="Random seed for reproducibility")
    
    args = parser.parse_args()
    
    if args.seed is not None:
        np.random.seed(args.seed)
        print(f"Using random seed: {args.seed}")
    
    generate_test_vectors(args.rows, args.cols, args.k_dim, args.data_width, args.out_dir)
