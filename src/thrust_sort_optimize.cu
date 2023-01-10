#include <chrono>
#include <iostream>
#include <thrust/device_free.h>
#include <thrust/device_malloc.h>
#include <thrust/device_ptr.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/sort.h>
#include <thrust_sort.cuh>

void print_vec(const thrust::host_vector<size_type> &vec) {
  for (auto &item : vec) {
    std::cout << item << " ";
  }
  std::cout << "\n";
}

__device__ uint64_t get_int(const uint64_t *m_data, const size_type idx,
                            const uint8_t len) {
  const uint64_t *word = m_data + (idx >> 6);
  const uint8_t offset = idx & 0x3F;
  uint64_t w1 = (*word) >> offset;
  if ((offset + len) > 64) { // if offset+len > 64
                             // w1 or w2 adepted:
    return w1 | ((*(word + 1) &
                  (1 << ((offset + len) & 0x3F)) - 1) // set higher bits zero
                 << (64 - offset));                   // move bits to the left
  } else {
    return w1 & ((1 << len) - 1);
  }
}

__global__ void test_get_int(const uint64_t *d_source, node_type *d_test,
                             const size_type vec_size,
                             const size_type start_idx, const int t_width) {
  size_type idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < vec_size) {
    d_test[idx] =
        get_int(d_source, size_type((start_idx + idx)) * t_width, t_width);
  }
  return;
}

__global__ void assign_key(const uint64_t *d_source,
                           const size_type *d_start_pos, node_type *d_keys,
                           size_type *d_seq_id, const size_type position,
                           const size_type first_seq_id,
                           const size_type seqs_size, const int t_width) {
  size_type idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < seqs_size) {
    d_keys[idx] = get_int(
        d_source,
        (d_start_pos[d_seq_id[idx] - first_seq_id] + position) * t_width,
        t_width);
  }
  return;
}

struct is_zero {
  __host__ __device__ bool operator()(int x) { return (x == 0); }
};

void 
radix_sort(const text_type &source, std::vector<size_type> &sequence_id,
           const std::unique_ptr<std::unordered_map<size_type, size_type>>
               &start_pos_map,
           std::vector<std::vector<std::pair<size_type, node_type>>> &sorted_seqs,
           const std::uint64_t total_nodes) {
  double init_time = 0, key_time = 0, /*h2d_copy_time = 0,*/ sort_time = 0,
         d2h_copy_time = 0, remove_time = 0, place_time = 0;
  std::chrono::steady_clock::time_point begin, end;
  begin = std::chrono::steady_clock::now();

  std::chrono::steady_clock::time_point sub_begin, sub_end;
  /*
  sub_begin = std::chrono::steady_clock::now();
  std::vector<std::vector<std::pair<size_type, node_type>>> sorted_seqs(
      total_nodes);
  sub_end = std::chrono::steady_clock::now();
  auto construct_vector_of_vector_time = std::chrono::duration<double>(sub_end-sub_begin);
  std::cout << "Pass construction of vector of vecotr.\n";
  std::cout << "Time Used: " << construct_vector_of_vector_time.count() << std::endl;
  */

  // ---- Prepare values to be used ---- //
  // width of the integers which are accessed via the [] operator
  const uint8_t t_width = source.width();
  const size_type source_size_byte = source.bit_size() / 8 + 1;
  const size_type seqs_size = (*start_pos_map).size(); // total sequence size
  size_type first_seq_id = sequence_id[0];

  // copy source to device memory
  // cudaMallocHost((void **)&source, source_size_byte, cudaHostAllocDefault);
  sub_begin = std::chrono::steady_clock::now();
  uint64_t *d_source;
  cudaMalloc(&d_source, source_size_byte);
  cudaMemcpyAsync(d_source, source.data(), source_size_byte,
                  cudaMemcpyHostToDevice);
  // cudaMemcpy(d_source, source.data(), source_size_byte,
  // cudaMemcpyHostToDevice);
  sub_end = std::chrono::steady_clock::now();
  auto device_malloc_and_pass_time = std::chrono::duration<double>(sub_end-sub_begin);
  std::cout << "Pass cuda malloc and copy async.\n";
  std::cout << "Time Used: " << device_malloc_and_pass_time.count() << std::endl;

  sub_begin = std::chrono::steady_clock::now();
  // copy start_position
  thrust::host_vector<size_type> start_pos;
  start_pos.reserve(seqs_size);
  for (auto &seq_id : sequence_id) {
    start_pos.push_back((*start_pos_map)[seq_id]);
  }
  thrust::device_vector<size_type> start_pos_vec = start_pos;
  size_type *d_start_pos = thrust::raw_pointer_cast(&start_pos_vec[0]);
  // thrust::device_ptr<size_type> d_start_pos =
  // start_pos_vec.data();
  sub_end = std::chrono::steady_clock::now();
  auto start_position_copy_time = std::chrono::duration<double>(sub_end-sub_begin);
  std::cout << "Pass copy start position to device.\n";
  std::cout << "Time Used: " << start_position_copy_time.count() << std::endl;

  sub_begin = std::chrono::steady_clock::now();
  // copy sequence_id
  thrust::host_vector<size_type> h_seq_id(sequence_id);
  thrust::device_vector<size_type> seq_id_vec = h_seq_id;
  thrust::device_ptr<size_type> d_seq_id =
      thrust::device_pointer_cast(&seq_id_vec[0]);
  size_type *d_seq_id_raw = thrust::raw_pointer_cast(&seq_id_vec[0]);
  // thrust::device_ptr<size_type> d_seq_id = seq_id_vec.data();
  sub_end = std::chrono::steady_clock::now();
  auto seq_id_copy_time = std::chrono::duration<double>(sub_end-sub_begin);
  std::cout << "Pass copy sequence id to device.\n";
  std::cout << "Time Used: " << seq_id_copy_time.count() << std::endl;

  sub_begin = std::chrono::steady_clock::now();
  // use gpu to assign keys
  // there about 2000~ sequences passed in
  thrust::host_vector<node_type> h_keys_vec(seqs_size);
  thrust::device_ptr<node_type> d_keys =
      thrust::device_malloc(sizeof(node_type) * seqs_size);
  node_type *d_keys_raw = thrust::raw_pointer_cast(d_keys);
  sub_end = std::chrono::steady_clock::now();
  auto key_alloc_time = std::chrono::duration<double>(sub_end-sub_begin);
  std::cout << "Pass allocate device mem for key.\n";
  std::cout << "Time Used: " << key_alloc_time.count() << std::endl;

  size_type arr_start_idx = 0;     // first index which is not an ENDMARKER
  size_type seqs_left = seqs_size; // sequences that have not
                                   // reached the ENDMARKER
  const int thread_per_block = 512;
  sub_begin = std::chrono::steady_clock::now();
  cudaDeviceSynchronize();
  sub_end = std::chrono::steady_clock::now();
  auto wait_sync_time = std::chrono::duration<double>(sub_end-sub_begin);
  std::cout << "Pass wait async memcpy for source.\n";
  std::cout << "Time Used: " << wait_sync_time.count() << std::endl;
  end = std::chrono::steady_clock::now();
  init_time = std::chrono::duration_cast<std::chrono::microseconds>(end - begin)
                  .count();

  for (size_type position = 0; seqs_left > 0; ++position) {
    //---- Assign Keys ----//
    begin = std::chrono::steady_clock::now();
    const int block_per_grid =
        (seqs_left + thread_per_block - 1) / thread_per_block;
    assign_key<<<block_per_grid, thread_per_block>>>(
        d_source, d_start_pos, d_keys_raw + arr_start_idx,
        d_seq_id_raw + arr_start_idx, position, first_seq_id, seqs_left,
        t_width);
    end = std::chrono::steady_clock::now();
    key_time +=
        std::chrono::duration_cast<std::chrono::microseconds>(end - begin)
            .count();

    //---- Radix Sort ----//
    begin = std::chrono::steady_clock::now();
    thrust::stable_sort_by_key(d_keys + arr_start_idx, d_keys + seqs_size,
                               d_seq_id + arr_start_idx);
    end = std::chrono::steady_clock::now();
    sort_time +=
        std::chrono::duration_cast<std::chrono::microseconds>(end - begin)
            .count();

    //---- Copy keys and sequence id back to host ----//
    begin = std::chrono::steady_clock::now();
    thrust::copy(d_seq_id + arr_start_idx, d_seq_id + seqs_size,
                 h_seq_id.begin());
    thrust::copy(d_keys + arr_start_idx, d_keys + seqs_size,
                 h_keys_vec.begin());
    end = std::chrono::steady_clock::now();
    d2h_copy_time +=
        std::chrono::duration_cast<std::chrono::microseconds>(end - begin)
            .count();

    //---- Remove paths that reaches the ENDMARKER(zero):  version2 ----//
    // remove: find the first index in h_keys_vec that is not an ENDMARKER
    ///*
    begin = std::chrono::steady_clock::now();
    size_type end_counter = 0;
    for (size_type i = 0; i < seqs_left; ++i) {
      if (h_keys_vec[i] != gbwt::ENDMARKER) {
        break;
      } else {
        ++end_counter;
      }
    }
    arr_start_idx += end_counter;
    seqs_left = seqs_size - arr_start_idx;
    end = std::chrono::steady_clock::now();
    remove_time +=
        std::chrono::duration_cast<std::chrono::microseconds>(end - begin)
            .count();
    if (seqs_left <= 0)
      break;
    //*/
    begin = std::chrono::steady_clock::now();
    for (size_type i = end_counter; i < seqs_left+end_counter; ++i) {
      size_type seq_id = h_seq_id[i];
      node_type next_node_id = source[(*start_pos_map)[seq_id] + position + 1];
      sorted_seqs[h_keys_vec[i] - 1].push_back({seq_id, next_node_id});
    }
    end = std::chrono::steady_clock::now();
    place_time +=
        std::chrono::duration_cast<std::chrono::microseconds>(end - begin)
            .count();
  }
  cudaFree(d_source);
  thrust::device_free(d_keys);
  std::cout << "init_time: " << init_time << " [μs]\n";
  std::cout << "key_time: " << key_time << " [μs]\n";
  std::cout << "d2h_copy_time: " << d2h_copy_time << " [μs]\n";
  std::cout << "sort_time: " << sort_time << " [μs]\n";
  std::cout << "remove_time: " << remove_time << " [μs]\n";
  std::cout << "place_time: " << place_time << " [μs]\n";
  /* print sorted_seqs
  int i = 1;
  for (auto &vec : sorted_seqs) {
    std::cout << "node_id: " << i++ << " ";
    for (auto &item : vec) {
      std::cout << "(" << item.first << ", " << item.second << ") ";
    }
    std::cout << "\n";
  }
  */
  /* print a specific sequence
  node_type node_id = 2;
  auto node2_vec = sorted_seqs[node_id - 1];
  for (auto &item : node2_vec) {
    std::cout << "(" << item.first << ", " << item.second << ")\n";
  }
  */
  // return sorted_seqs;
}

/*
// test section: get_int
node_type *d_test;
int start_idx = 99996850;
size_type vec_size = 10;
cudaMalloc(&d_test, sizeof(node_type) * vec_size);
int test_block = (vec_size + thread_per_block - 1) / thread_per_block;
test_get_int<<<test_block, thread_per_block>>>(d_source, d_test, vec_size,
                                             start_idx, t_width);
for (int i = start_idx; i < start_idx + vec_size; ++i) {
std::cout << source[i] << " ";
}
// std::cout << source.data()[start_idx] << "\n";
std::cout << "\n========================\n";
node_type *d_test_H = new node_type[vec_size + 1];
cudaMemcpy(d_test_H, d_test, sizeof(node_type) * vec_size,
         cudaMemcpyDeviceToHost);
for (int i = 0; i < vec_size; ++i) {
std::cout << d_test_H[i] << " ";
}
cudaFree(d_test);
delete[] d_test_H;
std::cout << "\n";
// test section: get_int
*/

/* test a specific sequence
for (size_type i = end_counter; i < (seqs_left / unroll_num);
     i += unroll_num) {
  size_type seq_id = h_seq_id[i];
  node_type next_node_id = source[(*start_pos_map)[seq_id] + position + 1];
  sorted_seqs[h_keys_vec[i] - 1].push_back({seq_id, next_node_id});
  if (seq_id == 716) {
    std::cout << "key: " << h_keys_vec[i] << "\n";
  }
}
*/
