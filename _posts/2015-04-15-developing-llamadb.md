---
layout: post
title: Developing LlamaDB - The pet SQL database
include_toc: true
---

# What is it?

<span style="font-size: 1.5em"><i class="fa fa-github fa-lg"></i> [LlamaDB project page](https://github.com/nukep/llamadb)</span>

LlamaDB is a home-grown SQL database that I began designing over the course of four weeks.
I'm developing LlamaDB to better understand the SQL language and its implementation details.

Of course, there are a plethora of existing database solutions:
MySQL, SQLite, PostgreSQL, MongoDB, etc.
**LlamaDB is not a replacement for any of these databases.**

As of writing, this is a solely a learning project for my benefit.

## Example

```sql
CREATE TABLE Album (
    AlbumId U32,
    Title STRING,
    ArtistId U32
);

CREATE TABLE Artist (
    ArtistId U32,
    Name STRING
);

INSERT INTO Artist (ArtistId, Name) VALUES
(1, 'AC/DC'),
(2, 'Accept'),
(3, 'Aerosmith'),
(4, 'Alanis Morissette'), /* many more rows... */;

INSERT INTO Album (AlbumId, Title, ArtistId) VALUES
(1, 'For Those About To Rock We Salute You', 1),
(2, 'Balls to the Wall', 2),
(3, 'Restless and Wild', 2),
(4, 'Let There Be Rock', 1), /* many more rows... */;

SELECT title AS album, name AS artist
FROM album, artist
WHERE album.artistid = artist.artistid;
/*
----------------------------------------------------------------------------------
| album                                            | artist                      |
----------------------------------------------------------------------------------
| For Those About To Rock We Salute You            | AC/DC                       |
| Let There Be Rock                                | AC/DC                       |
| Balls to the Wall                                | Accept                      |
| Restless and Wild                                | Accept                      |
| Big Ones                                         | Aerosmith                   |
| Jagged Little Pill                               | Alanis Morissette           |
| Facelift                                         | Alice In Chains             |
| Warner 25 Anos                                   | Antônio Carlos Jobim        |
                             ... many more rows ...
347 rows selected.
*/

SELECT (
    SELECT name FROM artist WHERE album.artistid = artist.artistid
) AS artist, count(*) album_count
FROM album
GROUP BY artistid;
/*
---------------------------------------
| artist                | album_count |
---------------------------------------
| AC/DC                 |           2 |
| Accept                |           2 |
| Aerosmith             |           1 |
| Alanis Morissette     |           1 |
| Alice In Chains       |           1 |
| Antônio Carlos Jobim  |           2 |
| Apocalyptica          |           1 |
| Audioslave            |           3 |
         ... many more rows ...
204 rows selected.
*/
```

# What can LlamaDB do?

**It can:**

* `CREATE TABLE`, `INSERT`, `SELECT`.
* Understand nested and correlated subqueries.
* Understand the `SELECT` clauses: `FROM`, `WHERE`, `GROUP BY`, `HAVING`, `SELECT`.
* Explain query execution plans.

**It cannot (yet):**

* `UPDATE` or `DELETE`.
* Understand inner and outer joins. Traditional cross-joins are used for the meanwhile (e.g. `WHERE`).
* Use indices. Scans are used for the meanwhile.
* Perform transactions of any kind.
* Do the other things listed in the [issue tracker](https://github.com/nukep/llamadb/issues).


tl;dr: It doesn't do much. If you want a feature-rich RDBMS, look elsewhere.

## Some gimmicks

Design decisions (not all yet implemented):

* Continues the long-held tradition, practiced by many RDBMS's, of _not_ conforming to the SQL standard.
* Columns are not nullable by default. Null still exists for outer joins, 3VL and aggregate functions, however.
* Integer types are named after their signedness and the number of bits they contain: `U8`, `U16`, `I8`, `I32`, etc.
* Every type has a binary representation that can be exposed through the SQL language.
* Eventual support for UUID, JSON, and bcrypt column types.


# Made with Rust

{% include rust-logo.html %}

Rust is the C++ we all deserve.

If you're a serious C or C++ developer, you're basically required to
consider the [Rust programming language](http://www.rust-lang.org).
Like C++, Rust is made to run close to the metal; it features zero-cost abstractions, RAII, and when compiled is nearly indistinguishable from equivalent C or C++ code.
Arguably the most important feature of the Rust programming language is its
memory safety guarantees and other invariant guarantees.
This means: no null pointer dereferences, no data races, no use-after-free, etc.
Segfaults are impossible unless the programmer bypasses Rust's safety checks
with `unsafe` blocks.

Oh, and did I mention built-in unit testing?

Relational databases have a requirement to be both _fast_ and _secure_.
I believe that Rust is great at meeting both of these requirements.

**Some useful Rust features used in LlamaDB (out of many):**

Rust's [enum types](http://doc.rust-lang.org/book/enums.html)
(also known as algebraic data types or tagged unions) are an immensely useful feature
that not enough languages have.
I used them for the AST, the column Variant type, and of course, error
enumerations.
Without ADTs, I'm almost certain that the AST module would've been lots of
`union` spaghetti.

The [`Result<T, E>`](http://doc.rust-lang.org/book/error-handling.html#handling-errors-with-option-and-result) "error handling" type is a _really good idea_.
It's a good alternative to the exception-based error handling patterns found in other programming languages. It's an enum that can either be `Ok(T)` or `Err(E)`, and must be used by the caller. In my experience, return-based error handling is better for recoverable errors than using try/catch (which in languages like C# can be neglected).
All non-fatal errors are return values, and all fatal errors are "panics" that unwind the stack and abort the program.

The `unsafe` keyword makes code and security audits much more streamlined.
If a segfault occurs in a Rust program, one can `Ctrl+F` for the word `unsafe`
and investigate. Undefined behavior bugs are now shallow.


# Implementation details

## Using recursion for query execution plans

Every notable SQL database that exists will compile SQL queries into a
language designed to target a machine used by the database.
This language will vary for each SQL vendor, but the principle is universal.

Real-world example: SQLite implements a ["virtual machine" language](https://www.sqlite.org/opcode.html) that resembles
the assembly languages found on CPUs (x86, ARM...) and other virtual machines (LLVM, JVM...).
All instructions are executed linearly, and looping constructs are performed with jumps.

My issue with assembly languages is that they're granular and require lots of foresight to design them well.
Instead of spending weeks meticulously planning the language on paper, I'd rather develop the language _iteratively_ (well, recursively that is).

As a programmer, I find that recursion is almost always easier to reason about.
Recursion is used everywhere in LlamaDB - it's used for the parser,
the AST, and of course, the query execution plan.

While it's true that recursion can introduce _nasties_ such as stack overflows,
SQL doesn't heavily nest; it's not a significant issue here.
Overall, I definitely wanted _easy_ instead of _complicated_.

SQL -> AST -> Query plan

**1. SQL:**

```sql
EXPLAIN SELECT * FROM person WHERE age >= 18;
```

**2. Abstract Syntax Tree (Rust-style):**

```rust
SelectStatement {
    result_columns: vec![SelectColumn::AllColumns],
    from: From::Cross(vec![TableOrSubquery::Table {
        table: Table { database_name: None, table_name: "person" },
        alias: None
    }]),
    where_expr: Expression::BinaryOp {
        op: BinaryOp::GreaterThanOrEqual,
        lhs: Expression::Ident("age"),
        rhs: Expression::Number("18")
    },
    group_by: vec![],
    having: None,
    order_by: vec![]
}
```


**3. Execution plan (Lisp-style notation):**

```lisp
(scan `person` :source-id 0
  (if
    (>=
      (column-field :source-id 0 :column-offset 2)
      18)
    (yield
      (column-field :source-id 0 :column-offset 1)
      (column-field :source-id 0 :column-offset 2))))
```

The above syntax more or less matches the query plan's internal data structure.
Like Lisp, it is [homoiconic](http://en.wikipedia.org/wiki/Homoiconicity).

* `scan` iterates through every row in a given table, and runs the provided expression for each row.
* `source-id` is a sort of "variable" that's scoped to the child nodes.
It's an identifier for a row or group.
* `if` evaluates a predicate expression, and runs the second expression if the predicate holds true.
* `column-field` resolves to a variant data type. The source-id identifies either a row or group.
* `yield` invokes a callback in Rust, signaling a row result.

## The lexer and parser

I originally intended on using a LALR(1) parser generator,
but alas, none of those exist for Rust yet.
There's the `rust-peg` project for PEG parsers, but I didn't know much about
PEG and wasn't completely sure about using a PEG parser at the time.

Both the lexer and parser components are hand-written. It actually wasn't as bad as it might seem.

The lexer is a very basic character-by-character tokenizer. In come characters, out go tokens.
There isn't much about this worth talking about.

The parser is a [recursive descent parser](http://en.wikipedia.org/wiki/Recursive_descent_parser), like many hand-written parsers in the wild.
This project single-handedly destroyed my pre-notion of "parsers are hard".
The truth is, certain types of languages are really easy to hand-parse using the
right techniques.

* The parser is approximately **700 lines of code** for all of `CREATE`, `INSERT` and `SELECT`.
* The lexer is appoximately 400 lines of code.
* The AST structures are approximately 150 lines of code.

As the name implies, top-down recursion is used to parse grammar rules.
To determine a rule, there is always a token lookahead of 1 and backtracking.

The AST structures were dead simple, thanks to Rust's enums (tagged unions).

Here's what the `Expression` AST looks like:

```rust
#[derive(Debug, PartialEq)]
pub enum Expression {
    Ident(String),
    // string1.string2
    IdentMember(String, String),
    StringLiteral(String),
    Number(String),
    Null,
    // name(argument1, argument2, argument3...)
    FunctionCall { name: String, arguments: Vec<Expression> },
    // name(*)
    FunctionCallAggregateAll { name: String },
    UnaryOp {
        expr: Box<Expression>,
        op: UnaryOp
    },
    // lhs op rhs
    BinaryOp {
        lhs: Box<Expression>,
        rhs: Box<Expression>,
        op: BinaryOp
    },
    Subquery(Box<SelectStatement>)
}
```


## Grouping confusion

While writing the compiler, a great deal of pain came from determining which queries and subqueries to group.
If an aggregate function references a query, then the query becomes automatically grouped if it wasn't already.
This is harder to deal with than it sounds.

SQL has some arcane grouping rules. Given the table `n1` with 101 inclusive rows ranged 0 to 100, what do each of the following queries do? How many rows do they yield?

Hint: all the queries are valid.

```sql
-- a)
SELECT a FROM n1;

-- b)
SELECT avg(a) FROM n1;  -- yields 50.0

-- c)
SELECT (SELECT avg(a.a + b.a) FROM n1 a) FROM n1 b;

-- d)
SELECT (SELECT avg(a.a + b.a) FROM n1 a), avg(b.a) FROM n1 b;

-- e)
SELECT (SELECT avg(a.a + avg(b.a)) FROM n1 a) FROM n1 b;

-- f)
SELECT (SELECT avg(a.a + b.a + avg(b.a)) FROM n1 a) FROM n1 b;
```

Number of rows: a) 101, b) 1, c) 101, d) 1, e) 1, f) 1

Results: a) 0 to 100, b) 50, c) 50 to 150, d) (any number from 50 to 150), 50, e) 100, f) (any number from 100 to 200)

It's commonly believed that that you can't call aggregate functions inside of
`WHERE`, `GROUP BY`, or other aggregate functions. Makes sense, right? As an implementer, I could simply
forbid all aggregate functions in those places just like SQLite does.
Well... it appears you actually _can_ use aggregate functions there (or rather should be able to).
As long as the aggregate function refers to an _outer query_, it works.
It's actually simpler implementation-wise to allow them.

* MySQL runs all the above queries.
* SQLite runs all except e) and f)
* PostgreSQL runs all except d) and f)
* LlamaDB runs all the above queries.

### Explanations

a) and b) are simple; they need no explanation.

For c), how do we decide which queries become groupped?

* LlamaDB auto-groups the _innermost_ query that gets referenced from an aggregate function call.
Two queries are referenced in the call: the `a` query and the `b` query.
The `a` query is more innermost than the `b` query, so `a` becomes groupped and `b` is left alone.
The `b` query runs the `a` query 101 times.

For d), which row is used for `b.a` in `avg(a.a + b.a)`?

* The `b` table is groupped from the aggregate call.
LlamaDB will pick any arbitrary row from that group; the exact row that's
used is undefined. In fact, MySQL and SQLite yield different
results for this query because of this detail.

For e), how does an aggregate call auto-group two queries? How are nested aggregate calls allowed?

* It doesn't, really. Aggregate calls nested inside other aggregate calls are treated
as separate expressions. They won't interfere as long as the aggregate functions work on different queries.
* The query would fail if a nested aggregate function _references the same query_. Example: `avg(a.a + avg(a.a))`.

f) combines the concepts found in d) and e).


## Lesson learned: SQL is hard

We database developers really take SQL for granted. That is a grotesquely massive understatement.
_So much_ goes on under the hood of mainstream databases that it might make your head spin.

In my experience, the hardest part about implementing SQL was the query compiler and query execution;
the query compiler took way longer to develop than anticipated.
Simple `SELECT` statements without aggregate functions or `GROUP BY` were fairly
straight forward to implement. **Groups**, however, were where the trouble began.

For the whole duration that I was implementing LlamaDB, I had this reoccurring
thought:

> SQL was invented in the 70's. How on earth did a group of computer scientists
envision and implement the entire SQL language back then?

Answer: They were wizards.
