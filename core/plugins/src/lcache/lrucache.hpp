#pragma once

#include <unordered_map>
#include <list>
#include <cstddef>
#include <stdexcept>
#include <string>
#include "fmt/format.h"

namespace cache {

	template<typename key_t, typename value_t>
	class lru_cache {
	public:
		typedef typename std::pair<key_t, value_t> key_value_pair_t;
		typedef typename std::list<key_value_pair_t>::iterator list_iterator_t;

		lru_cache(size_t max_size) :
			_max_size(max_size > 0 ? max_size : 1) {
		}
	
		void put(const key_t& key, const value_t& value) {
			auto it = _cache_items_map.find(key);
			if (it != _cache_items_map.end()) {			
				it->second->second = value;
				_cache_items_list.splice(_cache_items_list.begin(), _cache_items_list, it->second);
				return;
			}
			_cache_items_list.push_front(key_value_pair_t(key, value));
			_cache_items_map[key] = _cache_items_list.begin();

			if (_cache_items_map.size() > _max_size) {
				auto last = _cache_items_list.end();
				last--;
				_cache_items_map.erase(last->first);
				_cache_items_list.pop_back();
			}
		}
	
		const value_t& get(const key_t& key) {
			auto it = _cache_items_map.find(key);
			if (it == _cache_items_map.end()) {
				throw std::out_of_range(fmt::format("Key not found in cache: {}",key));
			} else {
				_cache_items_list.splice(_cache_items_list.begin(), _cache_items_list, it->second);
				return it->second->second;
			}
		}

		bool remove(const key_t& key) {
			auto it = _cache_items_map.find(key);
			if (it == _cache_items_map.end()) {
				return false; 
			}
			_cache_items_list.erase(it->second);
			_cache_items_map.erase(it);
			return true;
		}
	
		bool exist(const key_t& key) const {
			return _cache_items_map.find(key) != _cache_items_map.end();
		}
	
		size_t size() const {
			return _cache_items_map.size();
		}
	
	private:
		std::list<key_value_pair_t> _cache_items_list;
		std::unordered_map<key_t, list_iterator_t> _cache_items_map;
		size_t _max_size;
	};

} // namespace cache



