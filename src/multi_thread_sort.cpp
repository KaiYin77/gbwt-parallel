#include <multi_thread_sort.h>
#include <numeric>
#include <iostream>

MultiThreadSortClass::MultiThreadSortClass(
    std::vector<std::vector<int>>& _seqs, 
    std::vector<std::vector<std::pair<gbwt::size_type, gbwt::node_type>>>& _sorted_seqs, 
    int _thread_num): 
    thread_num(_thread_num), 
    bucket_num(0), 
    round(0), 
    round_num(0), 
    seqs(_seqs), 
    sorted_seqs(_sorted_seqs), 
    tmp_seqs(std::vector<std::vector<int>>(_seqs.size())), 
    rank(std::vector<int>(_seqs.size())), 
    tmp_rank(std::vector<int>(_seqs.size())){
    
    // count node number and round in radix sort
    for(const auto& seq: seqs){
        round_num = seq.size() > round_num ? seq.size() : round_num;
        bucket_num = seq.back() > bucket_num ? seq.back() : bucket_num;
    }

    // initialize rank
    std::iota(rank.begin(), rank.end(), 0);

    // initialize occurence list & offset list
    occ = std::vector<std::vector<int>>(thread_num, std::vector<int>(bucket_num + 1));
    off = std::vector<std::vector<int>>(thread_num, std::vector<int>(bucket_num + 1));
    sum = std::vector<int>(bucket_num + 1);

    // initialize thread list
    threads = std::vector<std::thread>(thread_num > bucket_num + 1 ? thread_num : bucket_num + 1);

    // initialize sorted sequences
    sorted_seqs = std::vector<std::vector<std::pair<gbwt::size_type, gbwt::node_type>>>(bucket_num);
}

void MultiThreadSortClass::sort(){
    while(round < round_num){
        // create task1(count occurence) threads
        for(int i = 0; i < thread_num; i++){
            threads[i] = std::thread(&MultiThreadSortClass::count_occ, this, i);
        }

        // wait threads
        wait();

        // create task2(count offset part1) threads
        for(int i = 0; i < bucket_num + 1; i++){
            threads[i] = std::thread(&MultiThreadSortClass::count_off1, this, i);
        }

        // wait threads
        wait();

        // create task3(count offset part2) threads
        for(int i = 0; i < bucket_num + 1; i++){
            threads[i] = std::thread(&MultiThreadSortClass::count_off2, this, i);
        }

        // wait threads
        wait();

        // create task4(count offset part3) threads
        for(int i = 0; i < bucket_num + 1; i++){
            threads[i] = std::thread(&MultiThreadSortClass::count_off3, this, i);
        }
        
        // wait threads
        wait();

        // create task5(adjust rank) threads
        for(int i = 0; i < thread_num; i++){
            threads[i] = std::thread(&MultiThreadSortClass::adjust_rank, this, i);
        }
        
        // wait threads
        wait();

        // get data back from temp arrays
        seqs.swap(tmp_seqs);
        rank.swap(tmp_rank);

        // collect ranks of this round
        collect_rank();
        round++;
    }
}

void MultiThreadSortClass::count_occ(int thread_id){
    // count range of this thread
    int slice = seqs.size() / thread_num;
    int begin_pos = slice * thread_id;
    int end_pos = (thread_id == thread_num - 1) ? seqs.size() : slice * (thread_id + 1);

    // reset vector
    occ[thread_id] = std::vector<int>(occ[thread_id].size(), 0);
    
    // count occurence
    for(int i = begin_pos; i < end_pos; i++){
        if(round < seqs[i].size()){
            occ[thread_id][seqs[i][round]-1]++;
        }
        else{
            occ[thread_id][bucket_num]++;
        }
    }
}

void MultiThreadSortClass::count_off1(int thread_id){
    for(int i = 0; i < thread_num; i++){
        off[i][thread_id] = 0;
    }
    for(int i = 1; i < thread_num; i++){
        off[i][thread_id] = off[i-1][thread_id] + occ[i-1][thread_id];
    }
}

void MultiThreadSortClass::count_off2(int thread_id){
    // count the sum of column in front of it
    sum[thread_id] = 0;
    for(int i = 0; i < thread_id; i++){
        sum[thread_id] += off.back()[i] + occ.back()[i];
    }
}

void MultiThreadSortClass::count_off3(int thread_id){
    for(int i = 0; i < thread_num; i++){
        off[i][thread_id] += sum[thread_id];
    }
}

void MultiThreadSortClass::adjust_rank(int thread_id){
    // count range of this thread
    int slice = seqs.size() / thread_num;
    int begin_pos = slice * thread_id;
    int end_pos = thread_id == thread_num - 1 ? seqs.size() : slice * (thread_id + 1);
    
    for(int i = begin_pos; i < end_pos; i++){
        int x = round < seqs[i].size() ? seqs[i][round] : bucket_num;
        tmp_seqs[off[thread_id][x-1]].swap(seqs[i]);
        tmp_rank[off[thread_id][x-1]] = rank[i];
        off[thread_id][x-1]++;
    }
}

void MultiThreadSortClass::collect_rank(){
    for(int i = 0; i < seqs.size(); i++){
        if(round < seqs[i].size()){
            int cur_rank = rank[i];
            int next = (round < seqs[i].size()-1) ? seqs[i][round+1] : 0;
            sorted_seqs[seqs[i][round]-1].push_back(std::pair<gbwt::size_type, gbwt::node_type>(cur_rank, next));
        }
    }
}

void MultiThreadSortClass::wait(){
    for(auto& thread: threads){
        if(thread.joinable()){
            thread.join();
        }
    }
}

// wrapper function taking input vector<vector<int>>>
/*void multi_thread_sort(std::vector<std::vector<int>>& seqs,
                             std::vector<std::vector<std::pair<gbwt::size_type, gbwt::node_type>>>& sorted_seqs){
    MultiThreadSortClass ssmtc(seqs, sorted_seqs, 100);
    ssmtc.sort();
}*/

// wrapper function taking input gbwt::text_type
void multi_thread_sort(const gbwt::text_type& text,
                             std::vector<gbwt::size_type>& seqs_id,
                             std::unique_ptr<std::unordered_map<gbwt::size_type, gbwt::size_type>>& start_pos_map,
                             std::vector<std::vector<std::pair<gbwt::size_type, gbwt::node_type>>>& sorted_seqs){
    std::vector<std::vector<int>> seqs(seqs_id.size());
    for(const auto &id: seqs_id){
        for(auto now = (*start_pos_map)[id]; text[now] != gbwt::ENDMARKER; now++){
            seqs[id].push_back(text[now]);
        }
    }
    MultiThreadSortClass mtsc(seqs, sorted_seqs, 100);
    mtsc.sort();
}