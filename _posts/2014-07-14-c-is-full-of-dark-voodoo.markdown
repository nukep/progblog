---
layout: post
title: C++ is full of dark voodoo
---
Alternate title: **You don't know C++ as well as you might think**

There is no doubt that C++ is a complex programming language.
It also goes without saying that almost nobody&mdash;not even seasoned developers&mdash;can fully grok the vastness that C++ has to offer. This Rube Goldberg of a programming language is full of gotchas and "features", and it is my view that you should  [never trust a programmer who says they know C++](http://lbrandy.com/blog/2010/03/never-trust-a-programmer-who-says-he-knows-c/).
If you're a C++ developer and you still feel cocky, take a few minutes to take the [C++11 Quiz](http://cppquiz.org/). If this doesn't destroy whatever positive feelings you had with the C++ language, you're probably insane.

Before continuing: This article assumes you have preliminary knowledge of RAII and C++ constructors. If you know what "The Rule of Three" is, you should be fine.

### Copy elision

In C, you are generally advised against returning structures in functions. Returning structures is expensive and pointless:

```c
struct foo bar_bad(const struct foo *src, int value)
{
	struct foo n;
    n.num = src->num + value;
    /* Copies n to return value - inefficient! */
    return n;
}

void bar_better(struct foo *dst, const struct foo *src, int value)
{
	/* Initializes value in pre-allocated space - efficient!
     * dst is also not limited to stack (can point to heap) */
	dst->num = src->num + value;
}
```

But in C++, return-by-value is the norm! This is pretty much mandated practice due to the unfortunate nature of how C++ constructors work.
Idiomatic C++ never leaves memory uninitialized, so you shouldn't just give a function a slate of uninitialized memory to work with as you would in C. You _can_, but it's frowned upon. C and C++ are different languages after all!

So great. That means we're stuck with the inefficient return-by-value way in C++, aren't we?
Well... who said C++ worked the same way that C does? :)

```c++
#include <iostream>

struct Foo {  
    int num;

    void log(const char* msg) const {
        std::cout << "[" << this << "] " << msg << std::endl;
    }

    Foo(int n) : num(n)
    { log("+ Foo(int)"); }

    Foo(const Foo& foo) : num(foo.num)  // copy constructor
    { log("+ Foo(const Foo&)"); }

    Foo(const Foo&& foo) : num(foo.num) // move constructor (C++11)
    { log("+ Foo(const Foo&&)"); }

    ~Foo()
    { log("- ~Foo()"); }

    static Foo bar(int value) {
        Foo a = {10 + value};
        a.log(" a");
        return a;
    }
};

int main() {  
    Foo b = Foo::bar(5);
    b.log(" b");
}
```

The above program demonstrates which constructors are called, and when. Most importantly, it tells us what happens when `Foo::bar()` returns a `Foo` value.

Program output: GCC 4.8.2, `g++ --std=c++11 -g rvo.cpp`:

<table>
<th>Optimized (gcc default)
</th>
<tr>
<td>
<pre>
[0xffb9e03c] + Foo(int)
[0xffb9e03c]  a
[0xffb9e03c]  b
[0xffb9e03c] - ~Foo()
</pre>
</td>
</tr>
</table>

That's interesting. Take a look at the addresses. No copying or moving was done.
In order to understand why, look at the variables `a` and `b`. Notice anything strange?

Both variables are allocated on the stack in what seems to be two different functions: `Foo::bar()` and its caller `main()`. But despite the two variable declarations existing separately, they occupy the same address of `0xffb9e03c`!

I was surprised by this finding. My original assumption was that because  `Foo::bar()` returns a value (and not a reference), `a` must always be moved to the return value using the copy or move constructor. What's happening here instead is an implementation-defined optimization, commonly known as **RVO** or **Return Value Optimization**. Instead of performing a needless move to the return value, possibly costing resources, *`a` is elided to the return value location*.

The most amazing/stupid thing about this optimization is that it is not required to take place. The compiler can decide whether or not to call the move constructor. If the move constructor differs from the observed behavior of not using one (prints `+ Foo(const Foo&&)`), *the compiler changes the output of the program!*

<table>
<th>Optimized</th>
<th>Not optimized</th>
<tr>
<td>
{% highlight c++ %}
static Foo bar(int value) {
    Foo a = {10 + value};
    a.log(" a");


    return a;
}
{% endhighlight %}
</td>
<td>
{% highlight c++ %}
static Foo bar(int value) {
    Foo a = {10 + value};
    a.log(" a");
    // cannot alias `a`
    if (value == 0) return {0};
    return a;
}
{% endhighlight %}
</td>
</tr>
<tr>
<td>
<pre>
[0xffb9e03c] + Foo(int)
<b>[0xffb9e03c]  a</b>


<b>[0xffb9e03c]  b</b>
[0xffb9e03c] - ~Foo()
</pre>
</td>
<td>
<pre>
[0xffb9e00c] + Foo(int)
<b>[0xffb9e00c]  a</b>
[0xffb9e03c] + Foo(const Foo&&)
[0xffb9e00c] - ~Foo()
<b>[0xffb9e03c]  b</b>
[0xffb9e03c] - ~Foo()
</pre>
</td>
</tr>
</table>

The C++ language asserts that redundant copies and moves may be eliminated, even if those copies and moves have other side-effects.

Despite its slightly ambiguous nature, this is useful. This means that trivial functions returning large structures is not as expensive.
