#pragma once

#include <vector>
#include <thread>
#include <gbwt/utils.h>

class MultiThreadSortClass{
private:
    int thread_num;                             // number of thread
    int bucket_num;                             // max node number
    int round;                                  // current round
    int round_num;                              // number of round that radix sort need to do
    std::vector<std::vector<int>>& seqs;        // input data
    std::vector<std::vector<std::pair<gbwt::size_type, gbwt::node_type>>>& sorted_seqs; // output data
    std::vector<std::vector<int>> tmp_seqs;
    std::vector<int> rank;                      // current rank of each sequence
    std::vector<int> tmp_rank;
    std::vector<std::thread> threads;           // thread list
    std::vector<std::vector<int>> occ;          // occurence of each digit of each thread
    std::vector<std::vector<int>> off;          // offset of each digit of each thread
    std::vector<int> sum;

public:
    MultiThreadSortClass(std::vector<std::vector<int>>& _seqs, 
                         std::vector<std::vector<std::pair<gbwt::size_type, gbwt::node_type>>>& _sorted_seqs, 
                         int thread_num);
    void sort();                                // main loop of sorting
    void count_occ(int thread_id);              // count occurence
    void count_off1(int thread_id);             // count offset of each column
    void count_off2(int thread_id);             // count offset of all columns before this
    void count_off3(int thread_id);             // add offset in count_off2()
    void adjust_rank(int thread_id);            // adjust elements' position and rank
    void collect_rank();                        // collect elements' rank
    void wait();                                // wait all threads to join
};

// wrapper function taking input vector<vector<int>>>
/*void multi_thread_sort(std::vector<std::vector<int>>& seqs,
                       std::vector<std::vector<std::pair<gbwt::size_type, gbwt::node_type>>>& sorted_seqs);*/

// wrapper function taking input gbwt::text_type
void multi_thread_sort(const gbwt::text_type& text,
                       std::vector<gbwt::size_type>& seqs_id,
                       std::unique_ptr<std::unordered_map<gbwt::size_type, gbwt::size_type>>& start_pos_map,
                       std::vector<std::vector<std::pair<gbwt::size_type, gbwt::node_type>>>& sorted_seqs);