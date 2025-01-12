#!/bin/bash

# Directory and file setup
TODO_DIR="$HOME/todo-app"
TODO_FILE="$TODO_DIR/todo_list.txt"
MONEY_FILE="$TODO_DIR/money_log.txt"
BALANCE=0

# Create necessary directories and files
mkdir -p "$TODO_DIR"
touch "$TODO_FILE" "$MONEY_FILE"

# Load existing balance from previous entries
if [[ -f "$MONEY_FILE" ]]; then
    BALANCE=$(awk -F'|' '{s+=$2} END {print s}' "$MONEY_FILE")
fi

# Display tasks with colors
display_tasks() {
    > /tmp/todo_display.txt
    if [ -s "$TODO_FILE" ]; then
        echo "Tasks:" >> /tmp/todo_display.txt
        while IFS='|' read -r TASK STATUS DATE TIME; do
            if [ "$STATUS" = "completed" ]; then
                echo -e "$(tput setaf 2)$TASK (Completed - Due: $DATE $TIME)$(tput sgr0)" >> /tmp/todo_display.txt
            else
                echo "$TASK (Due: $DATE $TIME)" >> /tmp/todo_display.txt
            fi
        done < "$TODO_FILE"
    else
        echo "No tasks available!" >> /tmp/todo_display.txt
    fi
    dialog --title "To-Do List" --no-lines --clear --begin 1 1 --cr-wrap --textbox /tmp/todo_display.txt 15 60
}

# Add a task
add_task() {
    TASK=$(dialog --title "Add Task" --inputbox "Enter your task:" 10 50 3>&1 1>&2 2>&3 3>&-)
    if [ ! -z "$TASK" ]; then
        DATE=$(dialog --title "Add Date" --calendar "Select the due date:" 10 50 3>&1 1>&2 2>&3 3>&-)
        TIME=$(dialog --title "Add Time" --timebox "Select the due time:" 10 50 3>&1 1>&2 2>&3 3>&-)
        if [ ! -z "$DATE" ] && [ ! -z "$TIME" ]; then
            echo "$TASK|pending|$DATE|$TIME" >> "$TODO_FILE"
            dialog --title "Success" --msgbox "Task added successfully!" 10 30
        else
            dialog --title "Error" --msgbox "Date or time not provided!" 10 30
        fi
    fi
}

# Mark task as complete
complete_task() {
    if [ ! -s "$TODO_FILE" ]; then
        dialog --title "Complete Task" --msgbox "No tasks to complete!" 10 30
        return
    fi

    declare -a MENU_ITEMS=()
    COUNTER=1
    while IFS='|' read -r TASK STATUS DATE TIME; do
        if [ "$STATUS" != "completed" ]; then
            MENU_ITEMS+=("$COUNTER" "$TASK (Due: $DATE $TIME)")
        fi
        ((COUNTER++))
    done < "$TODO_FILE"

    if [ ${#MENU_ITEMS[@]} -eq 0 ]; then
        dialog --title "Complete Task" --msgbox "No pending tasks to complete!" 10 40
        return
    fi

    CHOICE=$(dialog --title "Complete Task" --menu "Select a task to mark as complete:" 20 60 10 "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3 3>&-)

    if [ ! -z "$CHOICE" ]; then
        touch "$TODO_FILE.tmp"
        COUNTER=1
        while IFS='|' read -r TASK STATUS DATE TIME; do
            if [ $COUNTER -eq $CHOICE ]; then
                echo "$TASK|completed|$DATE|$TIME" >> "$TODO_FILE.tmp"
            else
                echo "$TASK|$STATUS|$DATE|$TIME" >> "$TODO_FILE.tmp"
            fi
            ((COUNTER++))
        done < "$TODO_FILE"
        mv "$TODO_FILE.tmp" "$TODO_FILE"
        dialog --title "Success" --msgbox "Task marked as complete!" 10 30
    fi
}

# Remove task
remove_task() {
    if [ ! -s "$TODO_FILE" ]; then
        dialog --title "Remove Task" --msgbox "No tasks to remove!" 10 30
        return
    fi

    declare -a MENU_ITEMS=()
    COUNTER=1
    while IFS='|' read -r TASK STATUS DATE TIME; do
        MENU_ITEMS+=("$COUNTER" "$TASK (Due: $DATE $TIME)")
        ((COUNTER++))
    done < "$TODO_FILE"

    CHOICE=$(dialog --title "Remove Task" --menu "Select a task to remove:" 20 60 10 "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3 3>&-)

    if [ ! -z "$CHOICE" ]; then
        touch "$TODO_FILE.tmp"
        COUNTER=1
        while IFS='|' read -r TASK STATUS DATE TIME; do
            if [ $COUNTER -ne $CHOICE ]; then
                echo "$TASK|$STATUS|$DATE|$TIME" >> "$TODO_FILE.tmp"
            fi
            ((COUNTER++))
        done < "$TODO_FILE"
        mv "$TODO_FILE.tmp" "$TODO_FILE"
        dialog --title "Success" --msgbox "Task removed successfully!" 10 30
    fi
}

# Money tracking functions
track_money() {
    dialog --menu "Money Tracker" 15 60 3 \
        1 "Add Income" \
        2 "Add Expense" \
        3 "View Transactions" \
        4 "Exit" 2>choice.txt
    choice=$(<choice.txt)
    case $choice in
        1) add_money "Income" ;;
        2) add_money "Expense" ;;
        3) view_transactions ;;
        4) return ;;
    esac
}

add_money() {
    type=$1
    amount=$(dialog --title "Add $type" --inputbox "Enter amount:" 10 40 3>&1 1>&2 2>&3 3>&-)

    if [ ! -z "$amount" ]; then
        reason=$(dialog --title "Add $type" --inputbox "Enter reason/description:" 10 50 3>&1 1>&2 2>&3 3>&-)

        if [[ "$type" == "Expense" ]]; then
            amount="-$amount"
        fi

        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$timestamp|$amount|$type|$reason" >> "$MONEY_FILE"
        BALANCE=$((BALANCE + amount))
        dialog --title "Success" --msgbox "$type added!\nTime: $timestamp" 6 40
    fi
}

view_transactions() {
    transactions=$(awk -F'|' '{printf "Time: %s\nAmount: %s\nType: %s\nReason: %s\n\n", $1, $2, $3, $4}' "$MONEY_FILE")
    if [ -z "$transactions" ]; then
        transactions="No transactions available!"
    fi
    dialog --title "Transaction History" --msgbox "$transactions" 20 80
}

view_balance() {
    monthly_summary=$(awk -F'|' '
        BEGIN { printf "Monthly Summary:\n" }
        {
            split($1, date, "-");
            month = date[1] "-" date[2];
            income[month] += ($3 == "Income" ? $2 : 0);
            expense[month] += ($3 == "Expense" ? $2 : 0);
        }
        END {
            for (m in income) {
                printf "%s:\n", m;
                printf "  Income: %10.2f\n", income[m];
                printf "  Expense: %10.2f\n", expense[m];
                printf "  Net: %13.2f\n\n", income[m] + expense[m];
            }
        }
    ' "$MONEY_FILE")

    dialog --title "Financial Summary" --msgbox "Current Balance: $BALANCE\n\n$monthly_summary" 20 60
}

# Main menu
main_menu() {
    CHOICE=$(dialog --title "Task & Money Manager" --menu "Choose an option:" 15 50 7 \
        1 "View Tasks" \
        2 "Add Task" \
        3 "Complete Task" \
        4 "Remove Task" \
        5 "Money Tracker" \
        6 "View Balance" \
        7 "Exit" \
        3>&1 1>&2 2>&3 3>&-)

    case $CHOICE in
        1) display_tasks ;;
        2) add_task ;;
        3) complete_task ;;
        4) remove_task ;;
        5) track_money ;;
        6) view_balance ;;
        7) exit 0 ;;
        *) dialog --title "Error" --msgbox "Invalid option!" 10 30 ;;
    esac
}

# Cleanup function
cleanup() {
    rm -f choice.txt /tmp/todo_display.txt
}

# Set cleanup trap
trap cleanup EXIT

# Main loop
while true; do
    main_menu
done
