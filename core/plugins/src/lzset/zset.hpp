#pragma once
#include <cstdint>
#include <set>
#include <unordered_map>
#include <vector>
#include <limits>
#include <string>
#include <cassert>

namespace lzset
{
    class zset
    {
        struct context
        {
            int64_t key = 0;
            std::vector<int64_t> scores = { 0 };
            size_t rank = 0;
        };

        struct compare
        {
            std::string fmt;
            compare() = default;
            compare(std::string v)
                :fmt(std::move(v))
            {
                for (auto c : v)
                {
                    assert(c == '>' || c == '<');
                }
            }

            bool operator()(context* a, context* b) const
            {
                for (size_t i=0;i<a->scores.size();++i)
                {
                    if (a->scores[i] == b->scores[i])
                    {
                        continue;
                    }
                    return fmt[i] == '>' ? (a->scores[i] > b->scores[i]) : (a->scores[i] < b->scores[i]);
                }
                return a->key < b->key;
            }
        };
    public:
        using container_type = std::set<context*, compare>;
        using iterator = typename container_type::iterator;
        using const_iterator = typename container_type::const_iterator;
        using pointer = typename container_type::pointer;
        using const_pointer = typename container_type::const_pointer;

        static constexpr size_t JUMP_STEP = 100;

        zset(size_t max_count = std::numeric_limits<size_t>::max(),size_t score_count = 1, std::string fmt = "><>>")
            :max_count_(max_count)
            ,score_count_(score_count)
            , cmp_(std::move(fmt))
            , order_(cmp_)
        {
        }

        int update(int64_t key, std::vector<int64_t> scores)
        {
            if (max_count_ == 0 || scores.size() != score_count_)
            {
                return 1;
            }

            auto iter = index_.find(key);
            if (index_.size() == max_count_ && iter == index_.end() && (cmp_.fmt[0] == '>'?((*(order_.rbegin()))->scores[0] > scores[0]): ((*(order_.rbegin()))->scores[0] < scores[0])))
            {
                return 2;
            }

            if (iter == index_.end())
            {
                iter = index_.emplace(key, context{ key, scores}).first;
            }
            else
            {
                order_.erase(&iter->second);
            }

            iter->second.scores = std::move(scores);
            order_.emplace(&iter->second);

            if (order_.size() > max_count_)
            {
                auto v = (*order_.rbegin());
                order_.erase(v);
                index_.erase(v->key);
            }

            ordered_ = false;
            return 0;
        }

        size_t rank(int64_t key)
        {
            prepare();
            auto iter = index_.find(key);
            if (iter != index_.end())
            {
                return iter->second.rank;
            }
            return 0;
        }

        void prepare()
        {
            if (!ordered_)
            {
                jump_.clear();
                size_t n = 0;
                for (auto iter = order_.begin(); iter != order_.end(); ++iter)
                {
                    if (n % JUMP_STEP == 0)
                    {
                        jump_.emplace_back(iter);
                    }
                    (*iter)->rank = ++n;
                }
                ordered_ = true;
            }
        }

        const std::vector<int64_t>& score(int64_t key) const
        {
            auto iter = index_.find(key);
            if (iter != index_.end())
            {
                return iter->second.scores;
            }
            static std::vector<int64_t> tmp = { 0 };
            return tmp;
        }

        const_iterator start(size_t nrank) const
        {
            size_t idx = nrank / JUMP_STEP;
            if (idx >= jump_.size())
            {
                return  order_.end();
            }

            for (auto iter = jump_[idx]; iter != order_.end(); ++iter)
            {
                if ((*iter)->rank == nrank)
                {
                    return iter;
                }
            }
            return  order_.end();
        }

        const_iterator begin() const
        {
            return order_.begin();
        }

        const_iterator end() const
        {
            return  order_.end();
        }

        size_t size() const
        {
            return order_.size();
        }

        bool has(int64_t key) const
        {
            return (index_.find(key) != index_.end());
        }

        void clear()
        {
            jump_.clear();
            order_.clear();
            index_.clear();
        }

        size_t erase(int64_t key)
        {
            auto iter = index_.find(key);
            if (iter != index_.end())
            {
                order_.erase(&iter->second);
                ordered_ = false;
                index_.erase(iter);
                return 1;
            }
            return 0;
        }
    private:
        const size_t max_count_;
        size_t score_count_ = 1;
        bool ordered_ = true;
        compare cmp_;
        std::vector<const_iterator> jump_;
        std::set<context*, compare> order_;
        std::unordered_map<int64_t, context> index_;
    };
}


