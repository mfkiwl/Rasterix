// RasterIX
// https://github.com/ToNi3141/RasterIX
// Copyright (c) 2024 ToNi3141

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#ifndef FIXED_SIZE_QUEUE_HPP
#define FIXED_SIZE_QUEUE_HPP

#include <array>
#include <cstdint>

namespace rr
{

template <typename T, std::size_t Size>
class FixedSizeQueue
{
public:
    FixedSizeQueue() = default;
    ~FixedSizeQueue() = default;

    /// @brief Adds an element to the back of the queue.
    /// @param val The element to add.
    inline void push_back(const T& val)
    {
        create_back() = val;
    }

    inline T& create_back()
    {
        if (m_head >= Size)
        {
            m_head = 0;
        }
        if (m_size < Size)
        {
            m_size++;
        }
        return m_data[m_head++];
    }

    /// @brief Returns the element at the specified index.
    ///     Size - 1 is the last element added. 0 is the first element added.
    /// @param index The index of the element to return.
    /// @return The element at the specified index.
    inline T& operator[](std::size_t index)
    {
        return m_data[calculateIndex(index)];
    }

    /// @brief Returns the element at the specified index.
    /// @param index The index of the element to return.
    /// @return The element at the specified index.
    inline const T& operator[](std::size_t index) const
    {
        return m_data[calculateIndex(index)];
    }

    /// @brief Returns the size of the queue.
    /// @return The size of the queue.
    inline std::size_t size() const
    {
        return m_size;
    }

    /// @brief Clears the queue.
    void clear()
    {
        m_head = 0;
        m_size = 0;
    }

    /// @brief Decreases the size of the queue.
    /// @param count The number of elements to remove.
    inline void removeElements(std::size_t count)
    {
        if (count > m_size)
        {
            m_size = 0;
        }
        else
        {
            m_size -= count;
        }
    };

private:
    inline std::size_t calculateIndex(uint32_t index) const
    {
        std::size_t newIndex = (m_head - m_size) + index;
        if (newIndex >= Size)
        {
            newIndex = newIndex + Size;
        }
        return newIndex;
    }

    std::array<T, Size> m_data;
    std::size_t m_head { 0 };
    std::size_t m_size { 0 };
};

} // namespace rr
#endif // FIXED_SIZE_QUEUE_HPP
